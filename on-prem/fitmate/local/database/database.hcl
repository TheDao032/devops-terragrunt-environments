# PostgreSQL provider config for the `database` units — SHARED across every database/<service>
# unit. Generated HERE (not hand-written in the shared module) so the module stays
# provider-config-free, exactly like the kube providers (root.hcl) and the vault provider
# (vault.hcl). INCLUDE this from every database unit:
#   include "root"     { path = find_in_parent_folders("root.hcl") }      # backend
#   include "database" { path = find_in_parent_folders("database.hcl") }  # postgresql provider (below)
#
# Connection values come from the ENV (same philosophy as vault.hcl's address/token). PASSWORD
# defaults to "" — the superuser (tf_admin) password only exists once provisioned, so a missing
# env var must not break parsing. Before applying a database unit, export them, e.g.:
#   export PG_HOST=192.168.105.10 PG_SUPERUSER=tf_admin PG_ADMIN_PASSWORD=...
locals {
  host               = get_env("PG_HOST", "192.168.105.10")
  port               = get_env("PG_PORT", "5432")
  superuser          = get_env("PG_SUPERUSER", "tf_admin")
  password           = get_env("PG_ADMIN_PASSWORD", "")
  database           = get_env("PG_CONNECT_DATABASE", "postgres")
  sslmode            = get_env("PG_SSLMODE", "prefer")
  provider_superuser = get_env("PG_PROVIDER_SUPERUSER", "true")
}

generate "postgresql_provider" {
  path      = "provider-postgresql.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "postgresql" {
  host     = "${local.host}"
  port     = ${local.port}
  username = "${local.superuser}"
  password = "${local.password}"
  database = "${local.database}"
  sslmode  = "${local.sslmode}"
  # true for our on-prem coordinator (a real superuser); false for managed/pooled endpoints
  # that forbid SET ROLE.
  superuser       = ${local.provider_superuser}
  connect_timeout = 15
  max_connections = 4
}
EOF
}
