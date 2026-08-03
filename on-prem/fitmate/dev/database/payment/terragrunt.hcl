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
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.dev}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

dependency "vault-secrets" {
  config_path = "../../vault-secrets"
  mock_outputs = {
    secrets = {
      "database/superuser/creds"   = { username = "tf_admin", password = "MOCK" }
      "database/payment/app/creds" = { username = "payment_app", password = "MOCK" }
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

  # payment-service — Escrow, audit log, wallets, withdrawals, gateway webhook events (data-model.md).
  # Constitutional tables: escrow_audit_log (§I), webhook_events (§IX) → `audit` schema.
  # ⚠️ WRITE-ONLY today: payment config/prod is DATABASE_WRITE_DB_CONNECTION_STRING only (gateway
  # integration unbuilt). So a single app (RW) role, NO read-only role yet. Add payment_ro + a
  # SELECT grant when a read consumer exists.
  services = {
    payment = {
      database = {
        name       = "payment"
        owner      = "payment_app"
        extensions = ["uuid-ossp"]
        schemas    = ["app", "audit"]
        # NO seed sql — owned by database/migrations/payment/ (constitution §V).
        pgbouncer = { register = false }
      }
      roles = {
        payment_app = { login = true, password = dependency.vault-secrets.outputs.secrets["database/payment/app/creds"]["password"] }
      }
      grants = []
    }
  }
}
