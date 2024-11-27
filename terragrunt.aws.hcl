# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform that provides extra tools for working with multiple Terraform modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Kube config vars
  # kube_config_vars    = read_terragrunt_config(find_in_parent_folders("kube-config.hcl"))
  # kube_host           = local.kube_config_vars.locals.host
  # kube_config_path    = local.kube_config_vars.locals.config_path
  # kube_config_context = local.kube_config_vars.locals.config_context

  # client_key             = local.kube_config_vars.locals.client_key
  # client_certificate     = local.kube_config_vars.locals.client_certificate
  # cluster_ca_certificate = local.kube_config_vars.locals.cluster_ca_certificate
  # token                  = local.kube_config_vars.locals.token

  # Vault config vars
  # vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault-config.hcl"))
  # vault_address     = local.vault_config_vars.locals.address
  # vault_token       = local.vault_config_vars.locals.token

  # Backend global vars
  # backend_vars      = read_terragrunt_config(find_in_parent_folders("backend.hcl"))
  # backend_hostname  = local.backend_vars.locals.hostname
  # backend_org       = local.backend_vars.locals.organization
  # backend_workspace = local.backend_vars.locals.workspaces_name

  # Automatically load region-level variables
  # location_vars = read_terragrunt_config(find_in_parent_folders("location.hcl"))
  # location      = local.location_vars.locals.location

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  # Automatically load region-level variables
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region      = local.region_vars.locals.aws_region

  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl", "fallback.hcl"))
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
}

# Generate an AWS provider block
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.region}"
}
EOF
}

# Configure Terragrunt to automatically store tfstate files in an S3 bucket
remote_state {
  backend = "s3"
  config = {
    encrypt = true
    bucket  = "nthedao-infra-${local.account_name}"
    key     = "${path_relative_to_include()}/terraform.tfstate"
    region  = "ap-southeast-1"
    // dynamodb_table = "apollo-infra-${local.account_name}-locks"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL PARAMETERS
# These variables apply to all configurations in this subfolder. These are automatically merged into the child
# `terragrunt.hcl` config via the include block.
# ---------------------------------------------------------------------------------------------------------------------

# Configure root level variables that all resources can inherit. This is especially helpful with multi-account configs
# where terraform_remote_state data sources are placed directly into the modules.
inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.environment_vars.locals,
)
