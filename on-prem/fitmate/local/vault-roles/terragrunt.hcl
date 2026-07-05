# locals {
#   environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
#   environment      = local.environment_vars.locals.environment
# }
#
# terraform {
#   # source = "../../../../../devops-terraform-modules//on-prem/vault-roles"
#   source = "../../../../../devops-terraform-modules//on-prem/vault-roles"
# }
#
# # Generate Kube providers
# generate "provider" {
#   path      = "provider-vault.tf"
#   if_exists = "overwrite_terragrunt"
#   contents  = <<EOF
#     provider "kubernetes" {
#       host                   = "${local.kube_host}"
#       client_key             = base64decode("${local.client_key}")
#       client_certificate     = base64decode("${local.client_certificate}")
#       cluster_ca_certificate = base64decode("${local.cluster_ca_certificate}")
#     }
#
#     provider "helm" {
#       kubernetes {
#         host                   = "${local.kube_host}"
#         client_key             = base64decode("${local.client_key}")
#         client_certificate     = base64decode("${local.client_certificate}")
#         cluster_ca_certificate = base64decode("${local.cluster_ca_certificate}")
#         token                  = "${local.token}"
#       }
#     }
#
#     provider "kubectl" {
#       apply_retry_count      = 1
#       load_config_file       = false
#
#       host                   = "${local.kube_host}"
#       client_key             = base64decode("${local.client_key}")
#       client_certificate     = base64decode("${local.client_certificate}")
#       cluster_ca_certificate = base64decode("${local.cluster_ca_certificate}")
#       token                  = "${local.token}"
#     }
#
#     # provider "vault" {
#     #   address = "${local.vault_address}"
#     #   token   = "${local.vault_token}"
#     #   skip_tls_verify = true
#     # }
#
#     provider "tls" {}
# EOF
# }
#
# dependency "vault" {
#   config_path = "../k3s-resources"
#   mock_outputs = {
#     vault_mount_path = "values"
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }
#
# include {
#   path = find_in_parent_folders("root.hcl")
# }
#
# inputs = {
#   # Overrides variables from env.hcl
#   # vault_mount_path = dependency.vault-secrets.outputs.vault_mount_path
#   roles = {
#     admin = [
#       {
#         path                  = "*"
#         data_capabilities     = "create,read,update,delete,list"
#         metadata_capabilities = "create,read,update,delete,list"
#         delete_capabilities   = "create,read,update,delete,list"
#         destroy_capabilities  = "create,read,update,delete,list"
#       }
#     ]
#     dev = [
#       {
#         path                  = "database/*"
#         data_capabilities     = "create,read,update,list"
#         metadata_capabilities = "create,read,update,list"
#         delete_capabilities   = "create,read,update,list"
#         destroy_capabilities  = "create,read,update,list"
#       },
#     ]
#     operation = [
#       {
#         path                  = "*"
#         data_capabilities     = "create,read,update,delete,list"
#         metadata_capabilities = "create,read,update,delete,list"
#         delete_capabilities   = "create,read,update,list"
#         destroy_capabilities  = "create,read,update,list"
#       }
#     ]
#     ]
#   }
# }
