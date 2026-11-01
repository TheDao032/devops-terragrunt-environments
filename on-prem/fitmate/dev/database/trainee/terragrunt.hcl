locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  pg_host  = get_env("PG_HOST", "192.168.105.10")
  ssh_host = get_env("PG_SSH_HOST", "192.168.105.10")
}

terraform {
  source = "../../../../../../devops-terraform-modules//on-prem/shared/database/postgresql"
}

# Reads passwords from vault-secrets → skip until Vault is up + unsealed (health-endpoint gate,
# same as the other units). Runtime prereqs (coordinator reachable + SSH) are not gated here.
exclude {
  if = run_cmd("--terragrunt-quiet", "bash", "-c",
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.fitmate}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

dependency "vault-secrets" {
  config_path = "../../vault-secrets"
  mock_outputs = {
    secrets = {
      "database/superuser/creds"   = { username = "tf_admin", password = "MOCK" }
      "database/trainee/app/creds" = { username = "trainee_app_${local.environment}", password = "MOCK" }
      "database/trainee/ro/creds"  = { username = "trainee_ro_${local.environment}", password = "MOCK" }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "postgresql" {
  path = find_in_parent_folders("postgresql.hcl")
}

inputs = {
  pg_host      = local.pg_host
  pg_port      = 5432
  pg_superuser = get_env("PG_SUPERUSER", "tf_admin")

  ssh_host = local.ssh_host
  ssh_user = get_env("PG_SSH_USER", "packer")
  ssh_opts = get_env("PG_SSH_OPTS", "-i ~/.ssh/lab_ed25519 -o StrictHostKeyChecking=accept-new -o BatchMode=yes")

  # trainee-service — Trainees, preferences, FitPoints balance (data-model.md).
  services = {
    trainee = {
      database = {
        name       = "trainee_${local.environment}"
        owner      = "trainee_app_${local.environment}"
        extensions = ["uuid-ossp"] # plain Postgres db (not Citus-sharded); add "citus" + per-db node registration to shard
        schemas    = ["app"]
        # NO seed sql — tables are owned by the service's migrations (database/migrations/trainee/),
        # per constitution §V (no manual SQL against any environment).
        pgbouncer = { register = false }
      }
      roles = {
        "trainee_app_${local.environment}" = { login = true, password = dependency.vault-secrets.outputs.secrets["database/trainee/app/creds"]["password"], conn_limit = 12 }
        "trainee_ro_${local.environment}"  = { login = true, password = dependency.vault-secrets.outputs.secrets["database/trainee/ro/creds"]["password"], conn_limit = 10 }
        # 🔴 SCRUM-550 — was 4, which DEADLOCKED every rolling update.
        #
        # A Postgres connection limit does not throttle, it REFUSES. During a
        # rolling update Kubernetes runs the OLD and NEW pod at the same time:
        # the old pod held all 4 read connections, the new pod's sqlx.Connect
        # was refused, it panicked, so it never became Ready, so the old pod was
        # never retired. Deleting the old pod does not help — its ReplicaSet
        # recreates it in seconds. Only scaling the Deployment to 0 broke it,
        # and that means a window with NO SERVICE.
        #
        # Measured 2026-11-01: this held a merged SECURITY fix out of dev for an
        # hour while Deployment spec, readyReplicas 1/1 and ArgoCD all read
        # green — they were describing a three-day-old pod.
        #
        # 10 = two pods x the app's read pool of 4 (trainee-service PR #92 makes
        # that ceiling real and config-driven; it was a hardcoded 25) + 2 spare
        # for the migrate Job. Both halves are required: the app ceiling alone
        # does not help, because the refusal happens at connect time, before
        # SetMaxOpenConns is ever reached.
        #
        # max_connections is 100 SERVER-WIDE across all 8 services, so this is
        # deliberately the smallest number that fits a rollout, not a round one.
      }
      grants = [
        # Tables live in `public`, NOT `app`: search_path is "$user", public, so every migration
        # creates its tables in public. Schema `app` is provisioned but has never held a table —
        # grants aimed at it applied cleanly and granted access to nothing (B-323a).
        { role = "trainee_ro_${local.environment}", schema = "public", object_type = "schema", privileges = ["USAGE"] },
        # EXISTING tables. Default privileges are future-only by definition, so tables created by
        # migrations that have ALREADY run need this present-tense grant (empty `objects` = all current).
        { role = "trainee_ro_${local.environment}", schema = "public", object_type = "table", privileges = ["SELECT"] },
        # FUTURE tables the app role creates (later migrations) — default privilege.
        { role = "trainee_ro_${local.environment}", schema = "public", object_type = "table", privileges = ["SELECT"], on_future = true, owner = "trainee_app_${local.environment}" },
      ]
    }
  }
}
