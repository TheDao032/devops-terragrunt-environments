locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

include {
  path = find_in_parent_folders()
}

terraform {
  # source = "../../../../../terraform-modules//aws/vpc"
  source = "git::git@github.com:TheDao032/devops-terraform-modules.git//aws/vpc?ref=${local.environment}"
}

inputs = {}
