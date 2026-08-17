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
      "database/inquiry/app/creds" = { username = "inquiry_app_${local.environment}", password = "MOCK" }
      "database/inquiry/ro/creds"  = { username = "inquiry_ro_${local.environment}", password = "MOCK" }
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

  # inquiry-service — Pre-booking messaging (data-model.md).
  services = {
    inquiry = {
      database = {
        name       = "inquiry_${local.environment}"
        owner      = "inquiry_app_${local.environment}"
        extensions = ["uuid-ossp"]
        schemas    = ["app"]
        # NO seed sql — owned by database/migrations/inquiry/ (constitution §V).
        pgbouncer = { register = false }
      }
      roles = {
        "inquiry_app_${local.environment}" = { login = true, password = dependency.vault-secrets.outputs.secrets["database/inquiry/app/creds"]["password"] }
        "inquiry_ro_${local.environment}"  = { login = true, password = dependency.vault-secrets.outputs.secrets["database/inquiry/ro/creds"]["password"] }
      }
      grants = [
        { role = "inquiry_ro_${local.environment}", schema = "app", object_type = "schema", privileges = ["USAGE"] },
        { role = "inquiry_ro_${local.environment}", schema = "app", object_type = "table", privileges = ["SELECT"], on_future = true, owner = "inquiry_app_${local.environment}" },
      ]
    }
  }
}
