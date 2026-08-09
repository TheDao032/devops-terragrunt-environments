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
      "database/superuser/creds" = { username = "tf_admin", password = "MOCK" }
      "database/admin/app/creds" = { username = "admin_app_${local.environment}", password = "MOCK" }
      "database/admin/ro/creds"  = { username = "admin_ro_${local.environment}", password = "MOCK" }
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

  # admin-service — admin/back-office data (PII-whitelisted, ADR-006). Go service, read+write DSN.
  services = {
    admin = {
      database = {
        name       = "admin_${local.environment}"
        owner      = "admin_app_${local.environment}"
        extensions = ["uuid-ossp"]
        schemas    = ["app"]
        # NO seed sql — owned by database/migrations/admin/ (constitution §V).
        pgbouncer = { register = false }
      }
      roles = {
        "admin_app_${local.environment}" = { login = true, password = dependency.vault-secrets.outputs.secrets["database/admin/app/creds"]["password"] }
        "admin_ro_${local.environment}"  = { login = true, password = dependency.vault-secrets.outputs.secrets["database/admin/ro/creds"]["password"] }
      }
      grants = [
        { role = "admin_ro_${local.environment}", schema = "app", object_type = "schema", privileges = ["USAGE"] },
        { role = "admin_ro_${local.environment}", schema = "app", object_type = "table", privileges = ["SELECT"], on_future = true, owner = "admin_app_${local.environment}" },
      ]
    }
  }
}
