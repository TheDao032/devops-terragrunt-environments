# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform that provides extra tools for working with multiple Terraform modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Kube config vars
  kube_config_vars    = read_terragrunt_config(find_in_parent_folders("kube-config.hcl"))
  kube_host           = local.kube_config_vars.locals.host
  kube_config_path    = local.kube_config_vars.locals.config_path
  kube_config_context = local.kube_config_vars.locals.config_context

  client_key             = local.kube_config_vars.locals.client_key
  client_certificate     = local.kube_config_vars.locals.client_certificate
  cluster_ca_certificate = local.kube_config_vars.locals.cluster_ca_certificate
  token                  = local.kube_config_vars.locals.token

  # Vault config vars
  vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault-config.hcl"))
  vault_address     = local.vault_config_vars.locals.address
  vault_token       = local.vault_config_vars.locals.token

  # Backend global vars
  backend_vars      = read_terragrunt_config(find_in_parent_folders("backend.hcl"))
  backend_hostname  = local.backend_vars.locals.hostname
  backend_org       = local.backend_vars.locals.organization
  backend_workspace = local.backend_vars.locals.workspaces_name

  # Automatically load region-level variables
  location_vars = read_terragrunt_config(find_in_parent_folders("location.hcl"))
  location      = local.location_vars.locals.location

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

# Generate providers
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
    terraform {
      required_version = "~> 1.9.0"

      required_providers {
        helm = {
          source  = "hashicorp/helm"
          version = "~> 2.15.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 2.25.0"
        }
        kubectl = {
          source  = "gavinbunney/kubectl"
          version = "~> 1.14.0"
        }
        vault = {
          source = "hashicorp/vault"
          version = "~> 4.4.0"
        }
      }
    }
EOF
}

# Generate Kube providers
generate "provider" {
  path      = "provider-kube.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
    provider "kubernetes" {
      host                   = "${local.kube_host}"
      client_key             = base64decode("${local.client_key}")
      client_certificate     = base64decode("${local.client_certificate}")
      cluster_ca_certificate = base64decode("${local.cluster_ca_certificate}")
    }

    provider "helm" {
      kubernetes {
        host                   = "${local.kube_host}"
        client_key             = base64decode("${local.client_key}")
        client_certificate     = base64decode("${local.client_certificate}")
        cluster_ca_certificate = base64decode("${local.cluster_ca_certificate}")
        token                  = "${local.token}"
      }
    }

    provider "kubectl" {
      apply_retry_count      = 1
      load_config_file       = false

      host                   = "${local.kube_host}"
      client_key             = base64decode("${local.client_key}")
      client_certificate     = base64decode("${local.client_certificate}")
      cluster_ca_certificate = base64decode("${local.cluster_ca_certificate}")
      token                  = "${local.token}"
    }

    provider "vault" {
      address = "${local.vault_address}"
      token   = "${local.vault_token}"
      skip_tls_verify = true
    }

    provider "tls" {}
EOF
}

# Generate Backend
# generate "backend" {
#   path = "backend.tf"
#   if_exists = "overwrite_terragrunt"
#   contents = <<EOF
#     terraform {
#       cloud {
#         hostname = "${local.backend_hostname}"
#         organization = "${local.backend_org}"
#         workspaces {
#           name = "${local.backend_workspace}"
#         }
#       }
#     }
# EOF
# }

# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL PARAMETERS
# These variables apply to all configurations in this subfolder. These are automatically merged into the child
# `terragrunt.hcl` config via the include block.
# ---------------------------------------------------------------------------------------------------------------------

# Configure root level variables that all resources can inherit. This is especially helpful with multi-account configs
# where terraform_remote_state data sources are placed directly into the modules.
inputs = merge(
  local.environment_vars.locals,
  local.backend_vars.locals,
  local.location_vars.locals,
  local.kube_config_vars.locals
)
