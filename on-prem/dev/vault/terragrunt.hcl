# locals {
#   environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
#   environment      = local.environment_vars.locals.environment
#   secrets          = local.environment_vars.locals.secrets
# }
#
# terraform {
#   source = "../../../../terraform-modules//on-prem/vault"
#   # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/vault?ref=${local.environment}"
# }
#
# # dependency "consul" {
# #   config_path = "../consul"
# #   skip_outputs = true
# #   mock_outputs = {
# #     id = "id"
# #     public_subnets = ["name1","name2"]
# #     private_subnets = ["name1","name2"]
# #     eks_securitygroup = "eks_security_group"
# #     eks_node_securitygroup = "eks_node_security_group"
# #   }
# #   mock_outputs_merge_strategy_with_state = "shallow"
# # }
#
# include {
#   path = find_in_parent_folders()
# }
#
# inputs = {
#   chart_version = "0.28.1"
#   namespace = "vault"
#   helm_repository = "https://helm.releases.hashicorp.com"
#   helm_release_name = "hashicorp-vault"
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
#       mount_path = "/vault/datastore"
#     }
#     auditstore = {
#       size = "10Gi"
#       mount_path = "/vault/auditstore"
#     }
#   }
#
#   injector_conf = {
#     resources = {
#       rq_mem    = "256Mi"
#       rq_cpu    = "250m"
#       limits_mem = "512Mi"
#       limits_cpu = "500m"
#     },
#   }
#
#   ui_conf = {
#     enabled = true
#   }
#
#   vault_hosts = [
#     {
#       host = "traefik.vault.local.com"
#       paths = [
#         "/"
#       ]
#     }
#   ]
#
#   vault_server_token = get_env("VAULT_MASTER_TOKEN", "hvs.6BcpGlzgfBseOdTavyAPWAxc")
#   consul_server_url = "consul-server:8500"
# }
