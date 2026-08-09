# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform that provides extra tools for working with multiple Terraform modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Kube provider config now lives in the shared backend.hcl (was per-tenant kube-config.hcl).
  kube_host           = local.backend_vars.locals.host
  kube_config_path    = local.backend_vars.locals.config_path
  kube_config_context = local.backend_vars.locals.config_context

  client_key             = local.backend_vars.locals.client_key
  client_certificate     = local.backend_vars.locals.client_certificate
  cluster_ca_certificate = local.backend_vars.locals.cluster_ca_certificate
  token                  = local.backend_vars.locals.token

  # Backend global vars (+ kube provider config, consolidated here)
  backend_vars      = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  backend_hostname  = local.backend_vars.locals.hostname
  backend_org       = local.backend_vars.locals.tf_organization
  backend_workspace = local.backend_vars.locals.tf_workspaces_name

  # Automatically load region-level variables
  location_vars = read_terragrunt_config(find_in_parent_folders("location.hcl"))
  location      = local.location_vars.locals.location

  # Automatically load environment-level variables
  organizaiton_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  organizaiton      = local.organizaiton_vars.locals.infras_organization

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
      required_version = "~> 1.11.2"

      required_providers {
        helm = {
          source  = "hashicorp/helm"
          version = "~> 3.2.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 3.2.1"
        }
        kubectl = {
          source  = "alekc/kubectl"
          version = "~> 2.4.1"
        }
        vault = {
          source = "hashicorp/vault"
          version = "~> 5.10.1"
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
      }
    }

    provider "kubectl" {
      apply_retry_count      = 3
      load_config_file       = false

      host                   = "${local.kube_host}"
      client_key             = base64decode("${local.client_key}")
      client_certificate     = base64decode("${local.client_certificate}")
      cluster_ca_certificate = base64decode("${local.cluster_ca_certificate}")
    }
EOF
}

# Generate Backend
# generate "backend" {
#   path      = "backend.tf"
#   if_exists = "overwrite_terragrunt"
#   contents  = <<EOF
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
  local.backend_vars.locals, # includes the kube provider config now
  local.location_vars.locals,
)
