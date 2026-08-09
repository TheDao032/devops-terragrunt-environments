locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/service-accounts"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "kube" {
  path = find_in_parent_folders("kube.hcl")
}

inputs = {
  # Overrides variables from env.hcl
}
