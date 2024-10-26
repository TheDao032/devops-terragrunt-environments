# locals {
#   environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
#   environment      = local.environment_vars.locals.environment
#   secrets          = local.environment_vars.locals.secrets
# }
#
# terraform {
#   source = "../../../../terraform-modules//on-prem/consul"
#   # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/consul?ref=${local.environment}"
# }
#
# include {
#   path = find_in_parent_folders()
# }
#
# inputs = {
#   chart_version = "1.5.3"
#   namespace = "vault"
#   helm_repository = "https://helm.releases.hashicorp.com"
#   helm_release_name = "hashicorp-consul"
#   helm_release_chart = "consul"
#
#   server_conf = {
#     resources = {
#       rq_mem    = "200Mi"
#       rq_cpu    = "100m"
#       limits_mem = "500Mi"
#       limits_cpu = "500m"
#     },
#     storage = {
#       size = "10Gi"
#     }
#   }
# }
