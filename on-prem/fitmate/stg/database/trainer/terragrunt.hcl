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
      "database/trainer/app/creds" = { username = "trainer_app_${local.environment}", password = "MOCK" }
      "database/trainer/ro/creds"  = { username = "trainer_ro_${local.environment}", password = "MOCK" }
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

  # trainer-service — Trainers, verification, availability, reviews summary (data-model.md).
  services = {
    trainer = {
      database = {
        name       = "trainer_${local.environment}"
        owner      = "trainer_app_${local.environment}"
        extensions = ["uuid-ossp"]
        schemas    = ["app"]
        # NO seed sql — owned by database/migrations/trainer/ (constitution §V).
        pgbouncer = { register = false }
      }
      roles = {
        "trainer_app_${local.environment}" = { login = true, password = dependency.vault-secrets.outputs.secrets["database/trainer/app/creds"]["password"] }
        "trainer_ro_${local.environment}"  = { login = true, password = dependency.vault-secrets.outputs.secrets["database/trainer/ro/creds"]["password"] }
      }
      grants = [
        { role = "trainer_ro_${local.environment}", schema = "app", object_type = "schema", privileges = ["USAGE"] },
        { role = "trainer_ro_${local.environment}", schema = "app", object_type = "table", privileges = ["SELECT"], on_future = true, owner = "trainer_app_${local.environment}" },
      ]
    }
  }
}
