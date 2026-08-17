# Vault provider config — SHARED across all on-prem tenants (was per-tenant vault.hcl).
# INCLUDE this from vault stacks only, NOT from root.hcl. Keeping it out of root.hcl means
# non-vault stacks (k3s-resources, cert-manager, ...) never get a vault provider they don't need.
#
# Usage in a vault stack's terragrunt.hcl:
#   include "root"  { path = find_in_parent_folders("root.hcl") }   # kube providers + backend
#   include "vault" { path = find_in_parent_folders("vault.hcl") }  # vault provider (generate below)
#
# Data-only readers (e.g. env.hcl, external-secrets) use:
#   read_terragrunt_config(find_in_parent_folders("vault.hcl")).locals.address  (or .vault_address)
#
# NOTE on local names: both `address`/`token` AND `vault_address`/`vault_token` are exposed as
# ALIASES so every existing reference keeps working (bosch/renesas/prod use address/token;
# fitmate/local used vault_address/vault_token).
#
# ADDRESS + TOKEN come from the ENV with EMPTY-STRING DEFAULTS on purpose: they only exist after
# Vault is created + unsealed, so a missing env var must NOT break parsing. Before applying a vault
# stack, export them, e.g.:
#   export VAULT_ADDR=http://vault.k3s.local
#   export VAULT_TOKEN=$(age -d -i ~/.config/chezmoi/key.txt \
#     ~/Projects/Infrastrutures/devops-tools/vagrant/vagrant-files/k3s/vault-init.age | jq -r .root_token)

locals {
  address = get_env("VAULT_ADDR", "")
  token   = get_env("VAULT_TOKEN", "")

  # Aliases — same values, alternate names kept for backward compatibility.
  vault_address = get_env("VAULT_ADDR", "")
  vault_token   = get_env("VAULT_TOKEN", "")
}

generate "vault_versions" {
  path      = "vault-versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10.1"
    }
  }
}
EOF
}

generate "vault_provider" {
  path      = "provider-vault.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "vault" {
  address = "${local.address}"
  token   = "${local.token}"

  # Vault serves HTTPS with a cert-manager PRIVATE CA the Terraform host doesn't trust; skip
  # verification for the provider's control-plane calls (lab). Harmless when VAULT_ADDR is http.
  skip_tls_verify = true
}
EOF
}
