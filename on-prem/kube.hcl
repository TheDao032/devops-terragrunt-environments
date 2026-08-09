locals {
  # Backend global vars (+ kube provider config, consolidated here)
  common_vars      = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  common_hostname  = local.common_vars.locals.hostname
  common_org       = local.common_vars.locals.tf_organization
  common_workspace = local.common_vars.locals.tf_workspaces_name

  # Kube provider config now lives in the shared backend.hcl (was per-tenant kube-config.hcl).
  kube_host           = local.common_vars.locals.host
  kube_config_path    = local.common_vars.locals.config_path
  kube_config_context = local.common_vars.locals.config_context

  client_key             = local.common_vars.locals.client_key
  client_certificate     = local.common_vars.locals.client_certificate
  cluster_ca_certificate = local.common_vars.locals.cluster_ca_certificate
  token                  = local.common_vars.locals.token
}


generate "kubernetes-versions" {
  path      = "kubernetes-versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
    terraform {
      required_version = ">= 1.11.2, < 2.0.0"

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
      }
    }
EOF
}

# Generate Kube providers
generate "kubernetes-provider" {
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
      kubernetes = {
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
