# Keycloak provider config for the keycloak/<realm> units — SHARED across every realm unit. Generated
# HERE (not in the shared module) so the module stays provider-config-free, exactly like the kube
# providers (root.hcl), the vault provider (env auto-config), and the postgresql provider (database.hcl).
# INCLUDE from every realm unit:
#   include "root"     { path = find_in_parent_folders("root.hcl") }       # backend + versions.tf
#   include "keycloak" { path = find_in_parent_folders("keycloak.hcl") }   # provider (below)
#
# Auth = password grant (admin-cli + the master-realm admin user/password). PASSWORD is a SECRET
# (= keycloak/admin/creds) → set KEYCLOAK_PASSWORD in .envrc.local; it defaults to "" so a missing var
# doesn't break parsing. Before applying a realm unit, export KEYCLOAK_URL / KEYCLOAK_USER / KEYCLOAK_PASSWORD.
# Upgrade path: a dedicated `terraform` service-account client (client-credentials) — no password.
locals {
  url       = get_env("KEYCLOAK_URL", "http://keycloak.k3s.prod")
  client_id = get_env("KEYCLOAK_CLIENT_ID", "admin-cli")
  username  = get_env("KEYCLOAK_USER", "admin")
  password  = get_env("KEYCLOAK_PASSWORD", "")
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
