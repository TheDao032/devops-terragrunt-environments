locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  pg_host  = get_env("PG_HOST", "192.168.105.10")
  ssh_host = get_env("PG_SSH_HOST", "192.168.105.10")
}

terraform {
  source = "../../../../../../devops-terraform-modules//on-prem/shared/database/postgresql"
}

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
      "database/booking/app/creds" = { username = "booking_app_${local.environment}", password = "MOCK" }
      "database/booking/ro/creds"  = { username = "booking_ro_${local.environment}", password = "MOCK" }
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

  # booking-service — Bookings, sessions, check-ins, disputes, cancellations + saga orchestrator
  # (data-model.md). `audit` schema for the outbox/audit rows.
  services = {
    booking = {
      database = {
        name       = "booking_${local.environment}"
        owner      = "booking_app_${local.environment}"
        extensions = ["uuid-ossp"]
        schemas    = ["app", "audit"]
        # NO seed sql — owned by database/migrations/booking/ (constitution §V).
        pgbouncer = { register = false }
      }
      roles = {
        "booking_app_${local.environment}" = { login = true, password = dependency.vault-secrets.outputs.secrets["database/booking/app/creds"]["password"] }
        "booking_ro_${local.environment}"  = { login = true, password = dependency.vault-secrets.outputs.secrets["database/booking/ro/creds"]["password"] }
      }
      grants = [
        # Tables live in `public`, NOT `app`: search_path is "$user", public, so every migration
        # creates its tables in public. Schema `app` is provisioned but has never held a table —
        # grants aimed at it applied cleanly and granted access to nothing (B-323a).
        { role = "booking_ro_${local.environment}", schema = "public", object_type = "schema", privileges = ["USAGE"] },
        # EXISTING tables. Default privileges are future-only by definition, so tables created by
        # migrations that have ALREADY run need this present-tense grant (empty `objects` = all current).
        { role = "booking_ro_${local.environment}", schema = "public", object_type = "table", privileges = ["SELECT"] },
        # FUTURE tables the app role creates (later migrations) — default privilege.
        { role = "booking_ro_${local.environment}", schema = "public", object_type = "table", privileges = ["SELECT"], on_future = true, owner = "booking_app_${local.environment}" },
      ]
    }
  }
}
