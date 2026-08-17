# Keycloak + Vault provider partial for REALM stacks — SHARED across on-prem tenants, used ONLY by the
# `keycloak/<realm>` units. Realm units push their generated client secrets into Vault, so they ALWAYS
# need BOTH the keycloak AND vault providers. Terraform allows only ONE required_providers block per
# module, so this partial declares BOTH (in one block) and generates BOTH provider configs.
#
# ⚠️ A realm stack must include ONLY `root` + `keycloak` — do NOT also include `vault.hcl`, or you get
# "Duplicate required providers configuration" + a provider-vault.tf generate-path clash. (`vault.hcl`
# stays the partial for vault-ONLY stacks; THIS file is the combined partial for realm stacks.)
#
# Usage in a realm stack's terragrunt.hcl:
#   include "root"     { path = find_in_parent_folders("root.hcl") }      # required_version + backend
#   include "keycloak" { path = find_in_parent_folders("keycloak.hcl") }  # keycloak + vault providers (below)
#
# Env (set before applying):
#   export KEYCLOAK_URL=http://keycloak.k3s.fitmate KEYCLOAK_USER=admin KEYCLOAK_PASSWORD=...
#   export VAULT_ADDR=http://vault.k3s.fitmate      VAULT_TOKEN=...
# Auth = password grant (admin-cli + master-realm admin); PASSWORD is a SECRET (keycloak/admin/creds).
locals {
  url       = get_env("KEYCLOAK_URL", "http://keycloak.k3s.fitmate")
  client_id = get_env("KEYCLOAK_CLIENT_ID", "admin-cli")
  username  = get_env("KEYCLOAK_USER", "admin")
  password  = get_env("KEYCLOAK_PASSWORD", "")

  # Vault provider (the module pushes generated client secrets into Vault). Empty defaults so a missing
  # env var doesn't break parsing before Vault exists/is unsealed.
  vault_address = get_env("VAULT_ADDR", "")
  vault_token   = get_env("VAULT_TOKEN", "")
}

# ONE required_providers block for the whole realm module (keycloak + vault). Terraform permits only one
# per module — this is why realm units must NOT also include vault.hcl (which emits its own vault_versions).
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
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10.1"
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

# Vault provider for the client-secret push (mirrors vault.hcl's provider-vault.tf; distinct generate
# NAME so nothing collides, but SAME path — which is why a realm unit must not also include vault.hcl).
generate "keycloak_vault_provider" {
  path      = "provider-vault.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "vault" {
  address = "${local.vault_address}"
  token   = "${local.vault_token}"

  # Vault serves HTTPS with a cert-manager PRIVATE CA the Terraform host doesn't trust; skip
  # verification for the provider's control-plane calls (lab). Harmless when VAULT_ADDR is http.
  skip_tls_verify = true
}
EOF
}
