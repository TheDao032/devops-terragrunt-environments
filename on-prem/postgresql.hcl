# PostgreSQL provider partial — SHARED across all on-prem tenants. INCLUDE only from stacks that use
# the postgresql provider (the `database/<svc>` units). Self-contained: declares its own
# required_providers so a database stack no longer inherits kubernetes/helm/kubectl/vault/keycloak
# from root.hcl. Replaces the per-dir `database.hcl` copies.
#
# Usage in a database stack's terragrunt.hcl:
#   include "root"       { path = find_in_parent_folders("root.hcl") }        # required_version + backend + inputs
#   include "postgresql" { path = find_in_parent_folders("postgresql.hcl") }  # provider (below)
#
# Connection comes from the ENV (empty/default so parsing never fails before it's exported):
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

generate "postgresql_versions" {
  path      = "postgresql-versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.27.0"
    }
  }
}
EOF
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
