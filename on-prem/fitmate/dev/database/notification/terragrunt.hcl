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
      "database/superuser/creds"        = { username = "tf_admin", password = "MOCK" }
      "database/notification/app/creds" = { username = "notification_app_${local.environment}", password = "MOCK" }
      "database/notification/ro/creds"  = { username = "notification_ro_${local.environment}", password = "MOCK" }
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

  # notification-service — in-app notification inbox (SCRUM-427, spec 077 / ADR-090 A1).
  # One table today: user_notifications (the inbox read model).
  services = {
    notification = {
      database = {
        name  = "notification_${local.environment}"
        owner = "notification_app_${local.environment}"
        # Declared for fleet consistency — every peer DB carries it. NOTE for the next reader:
        # the current migration does NOT need it. 001_create_user_notifications.up.sql uses
        # `gen_random_uuid()`, which is CORE from PostgreSQL 13 on, not uuid-ossp's
        # `uuid_generate_v4()`. Verified empirically rather than from the version string:
        # payment-service's migrations already use gen_random_uuid() with no pgcrypto/uuid-ossp
        # requirement and have applied cleanly on this same server. Kept so a later migration
        # reaching for uuid_generate_v4() does not fail on a missing extension.
        extensions = ["uuid-ossp"]
        schemas    = ["app"]
        # NO seed sql — owned by the service's migrations/ (constitution §V).
        pgbouncer = { register = false }
      }
      roles = {
        "notification_app_${local.environment}" = { login = true, password = dependency.vault-secrets.outputs.secrets["database/notification/app/creds"]["password"] }
        "notification_ro_${local.environment}"  = { login = true, password = dependency.vault-secrets.outputs.secrets["database/notification/ro/creds"]["password"] }
      }
      grants = [
        # Grants target `public`, NOT `app` — B-323a. search_path is "$user", public, so migrations
        # create their tables in public; `app` is provisioned but has never held a table, and grants
        # aimed at it apply GREEN while granting access to nothing.
        { role = "notification_ro_${local.environment}", schema = "public", object_type = "schema", privileges = ["USAGE"] },
        # EXISTING tables — default privileges are future-only by definition, so anything created by
        # an already-applied migration needs this present-tense grant (empty `objects` = all current).
        { role = "notification_ro_${local.environment}", schema = "public", object_type = "table", privileges = ["SELECT"] },
        # FUTURE tables the app role creates — default privilege.
        { role = "notification_ro_${local.environment}", schema = "public", object_type = "table", privileges = ["SELECT"], on_future = true, owner = "notification_app_${local.environment}" },
      ]
    }
  }
}
