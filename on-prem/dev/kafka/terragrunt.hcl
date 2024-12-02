# locals {
#   environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
#   environment      = local.environment_vars.locals.environment
#   # secrets          = local.environment_vars.locals.secrets
# }
#
# terraform {
#   source = "../../../../terraform-modules//on-prem/kafka"
#   # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/kafka?ref=${local.environment}"
# }
#
# dependency "vault-secrets" {
#   config_path = "../vault-secrets"
#   mock_outputs = {
#     kafka_secrets = {
#       "kafka/creds" = {
#         clientUsername = "value"
#         clientPassword = "value"
#       }
#     }
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }
#
# include {
#   path = find_in_parent_folders()
# }
#
# inputs = {
#   chart_version = "30.1.6"
#   image_tag = "3.8.0-debian-12-r5"
#   namespace = "kafka"
#   helm_repository = "https://charts.bitnami.com/bitnami"
#   helm_release_name = "kafka"
#   helm_release_chart = "kafka"
#
#   controller_conf = {
#     replica_count = 1
#     hpa_active    = true
#     mount_path    = "/bitnami/kafka/controller"
#     min_replicas  = 1
#     max_replicas  = 3
#   }
#
#   broker_conf = {
#     replica_count = 1
#     hpa_active    = true
#     mount_path    = "/bitnami/kafka/broker"
#     min_replicas  = 1
#     max_replicas  = 3
#   }
#
#   sasl_conf = {
#     client = {
#       username: dependency.vault-secrets.outputs.kafka_secrets["kafka/creds"]["clientUsername"]
#       password: dependency.vault-secrets.outputs.kafka_secrets["kafka/creds"]["clientPassword"]
#     }
#   }
# }
