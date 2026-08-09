# Keycloak provider partial — SHARED across all on-prem tenants. INCLUDE only from stacks that use
# the keycloak provider (the `keycloak/<realm>` realm units). Self-contained: declares its own
# required_providers so a realm stack no longer inherits kubernetes/helm/kubectl from root.hcl.
# Replaces the per-dir `keycloak.hcl` copies. NOTE: realm units ALSO include `vault` (the module
# pushes generated client secrets into Vault).
#
# Usage in a realm stack's terragrunt.hcl:
#   include "root"     { path = find_in_parent_folders("root.hcl") }      # required_version + backend
#   include "vault"    { path = find_in_parent_folders("vault.hcl") }     # vault provider (secret push)
#   include "keycloak" { path = find_in_parent_folders("keycloak.hcl") }  # keycloak provider (below)
#
# Auth = password grant (admin-cli + master-realm admin). PASSWORD is a SECRET (keycloak/admin/creds)
# → set KEYCLOAK_PASSWORD in .envrc.local; defaults to "" so a missing var doesn't break parsing.
#   export KEYCLOAK_URL=http://keycloak.k3s.fitmate KEYCLOAK_USER=admin KEYCLOAK_PASSWORD=...
locals {
  url       = get_env("KEYCLOAK_URL", "http://keycloak.k3s.fitmate")
  client_id = get_env("KEYCLOAK_CLIENT_ID", "admin-cli")
  username  = get_env("KEYCLOAK_USER", "admin")
  password  = get_env("KEYCLOAK_PASSWORD", "")
}

generate "keycloak_versions" {
  path      = "keycloak-versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.9"
    }
  }
}
EOF
}

generate "keycloak_provider" {
  path      = "provider-keycloak.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "keycloak" {
  client_id = "${local.client_id}"
  username  = "${local.username}"
  password  = "${local.password}"
  url       = "${local.url}"
  # Keycloak >= 17 (Quarkus) serves at the root — no legacy /auth base_path.
}
EOF
}
