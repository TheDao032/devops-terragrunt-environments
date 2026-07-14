# Vault provider config — INCLUDE this from vault stacks only (vault-userpass, vault-roles,
# vault-secrets), NOT from root.hcl. Keeping it out of root.hcl means non-vault stacks
# (k3s-resources, cert-manager, ...) never get a vault provider they don't need.
#
# Usage in a vault stack's terragrunt.hcl:
#   include "root"  { path = find_in_parent_folders("root.hcl") }        # kube providers + backend
#   include "vault" { path = find_in_parent_folders("vault-config.hcl") } # vault provider
#
# ADDRESS + TOKEN come from the ENV with EMPTY-STRING DEFAULTS on purpose: they only exist
# after Vault is created + unsealed, so a missing env var must NOT break `terragrunt`/`terraform`
# parsing. Before applying a vault stack, export them, e.g.:
#   export VAULT_ADDR=http://vault.k3s.local
#   export VAULT_TOKEN=$(age -d -i ~/.config/chezmoi/key.txt \
#     ~/Projects/Infrastrutures/devops-tools/vagrant/vagrant-files/k3s/vault-init.age | jq -r .root_token)

locals {
  vault_address = get_env("VAULT_ADDR", "")
  vault_token   = get_env("VAULT_TOKEN", "")
}

generate "vault_provider" {
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
