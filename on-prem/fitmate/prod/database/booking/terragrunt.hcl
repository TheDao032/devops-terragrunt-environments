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
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.prod}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

dependency "vault-secrets" {
  config_path = "../../vault-secrets"
  mock_outputs = {
    secrets = {
      "database/superuser/creds"   = { username = "tf_admin", password = "MOCK" }
      "database/booking/app/creds" = { username = "booking_app", password = "MOCK" }
      "database/booking/ro/creds"  = { username = "booking_ro", password = "MOCK" }
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

  # booking-service — Bookings, sessions, check-ins, disputes, cancellations + saga orchestrator
  # (data-model.md). `audit` schema for the outbox/audit rows.
  services = {
    booking = {
      database = {
        name       = "booking"
        owner      = "booking_app"
        extensions = ["uuid-ossp"]
        schemas    = ["app", "audit"]
        # NO seed sql — owned by database/migrations/booking/ (constitution §V).
        pgbouncer = { register = false }
      }
      roles = {
        booking_app = { login = true, password = dependency.vault-secrets.outputs.secrets["database/booking/app/creds"]["password"] }
        booking_ro  = { login = true, password = dependency.vault-secrets.outputs.secrets["database/booking/ro/creds"]["password"] }
      }
      grants = [
        { role = "booking_ro", schema = "app", object_type = "schema", privileges = ["USAGE"] },
        { role = "booking_ro", schema = "app", object_type = "table", privileges = ["SELECT"], on_future = true, owner = "booking_app" },
      ]
    }
  }
}
