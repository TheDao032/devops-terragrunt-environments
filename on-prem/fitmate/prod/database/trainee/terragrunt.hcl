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
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.prod}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

dependency "vault-secrets" {
  config_path = "../../vault-secrets"
  mock_outputs = {
    secrets = {
      "database/superuser/creds"   = { username = "tf_admin", password = "MOCK" }
      "database/trainee/app/creds" = { username = "trainee_app", password = "MOCK" }
      "database/trainee/ro/creds"  = { username = "trainee_ro", password = "MOCK" }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "database" {
  path = find_in_parent_folders("database.hcl")
}

inputs = {
  pg_host      = local.pg_host
  pg_port      = 5432
  pg_superuser = get_env("PG_SUPERUSER", "tf_admin")

  ssh_host = local.ssh_host
  ssh_user = get_env("PG_SSH_USER", "packer")
  ssh_opts = get_env("PG_SSH_OPTS", "-i ~/.ssh/lab_ed25519 -o StrictHostKeyChecking=accept-new -o BatchMode=yes")

  # trainee-service — Trainees, preferences, FitPoints balance (data-model.md).
  # SHARED-PLATFORM PROD (2026-08-02, [[production-cloudflare-tunnel]] Phase 1): prod-SUFFIXED db + roles
  # so prod does NOT collide with / co-mingle local's `trainee` db on the SAME Postgres (192.168.105.10).
  # db=trainee_prod, roles=trainee_prod_app/ro. Vault password paths stay prod-isolated by folder
  # (fitmate/data/prod/database/trainee/...). The service key stays `trainee` (logical name).
  services = {
    trainee = {
      database = {
        name       = "trainee_prod"
        owner      = "trainee_prod_app"
        extensions = ["uuid-ossp"] # plain Postgres db (not Citus-sharded); add "citus" + per-db node registration to shard
        schemas    = ["app"]
        # NO seed sql — tables are owned by the service's migrations (database/migrations/trainee/),
        # per constitution §V (no manual SQL against any environment).
        pgbouncer = { register = false }
      }
      roles = {
        trainee_prod_app = { login = true, password = dependency.vault-secrets.outputs.secrets["database/trainee/app/creds"]["password"] }
        trainee_prod_ro  = { login = true, password = dependency.vault-secrets.outputs.secrets["database/trainee/ro/creds"]["password"] }
      }
      grants = [
        { role = "trainee_prod_ro", schema = "app", object_type = "schema", privileges = ["USAGE"] },
        # SELECT on FUTURE tables trainee_prod_app creates (i.e. migration tables) — default privilege.
        { role = "trainee_prod_ro", schema = "app", object_type = "table", privileges = ["SELECT"], on_future = true, owner = "trainee_prod_app" },
      ]
    }
  }
}
