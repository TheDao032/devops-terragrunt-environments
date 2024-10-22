# locals {
#   environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
#   environment      = local.environment_vars.locals.environment
#   secrets          = local.environment_vars.locals.secrets
# }
#
# terraform {
#   source = "../../../../terraform-modules//on-prem/vault-secrets"
#   # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/vault?ref=${local.environment}"
# }
#
# include {
#   path = find_in_parent_folders()
# }
#
# inputs = {
#   chart_version = "0.28.1"
#   namespace = "secret-management"
#   helm_repository = "https://helm.releases.hashicorp.com"
#   helm_release_name = "hashicorp"
#   helm_release_chart = "vault"
#
#   server_conf = {
#     resources = {
#       rq_mem    = "512Mi"
#       rq_cpu    = "250m"
#       limits_mem = "1Gi"
#       limits_cpu = "500m"
#     },
#     datastore = {
#       size = "10Gi"
#       mount_path = "/vault/data"
#     }
#   }
#   ui_conf = {
#     enabled = true
#   }
#   vault_hosts = [
#     {
#       host = "traefik.vault.local.com"
#       paths = [
#         "/"
#       ]
#     }
#   ]
# }
