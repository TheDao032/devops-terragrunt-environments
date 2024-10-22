locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../terraform-modules//on-prem/vault-secrets"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/vault-secrets?ref=${local.environment}"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  # Overrides variables from env.hcl
  kv_secret_path = "kv"
}
