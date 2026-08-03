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
      "database/superuser/creds"    = { username = "tf_admin", password = "MOCK" }
      "database/keycloak/app/creds" = { username = "keycloak_app", password = "MOCK" }
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

  # Keycloak's own database. Keycloak owns it and runs its OWN Liquibase schema migrations, so:
  #   - keycloak_app is the owner (full DDL); NO read-only role, NO schemas (Keycloak uses public),
  #     NO seed sql (Keycloak migrates itself on first boot).
  #   - pgbouncer.register = FALSE: Keycloak must connect DIRECT to the coordinator :5432. Its DB
  #     migrations take Postgres advisory locks + use prepared statements, which pgbouncer
  #     transaction pooling (:6432) breaks. The Keycloak CR points at <lb>:5432/keycloak.
  services = {
    keycloak = {
      database = {
        name       = "keycloak"
        owner      = "keycloak_app"
        extensions = []
        schemas    = []
        pgbouncer  = { register = false }
      }
      roles = {
        keycloak_app = { login = true, password = dependency.vault-secrets.outputs.secrets["database/keycloak/app/creds"]["password"] }
      }
      grants = []
    }
  }
}
