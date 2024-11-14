# locals {
#   environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
#   environment      = local.environment_vars.locals.environment
#   # secrets          = local.environment_vars.locals.secrets
# }
#
# terraform {
#   source = "../../../../terraform-modules//on-prem/jenkins"
#   # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
# }
#
# dependency "vault-secrets" {
#   config_path = "../vault-secrets"
#   mock_outputs = {
#     jenkins_secrets = {
#       username = "value"
#       password = "value"
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
#   chart_version = "5.7.3"
#   image_tag = "2.479-jdk17"
#   namespace = "jenkins"
#   helm_repository = "https://charts.jenkins.io/"
#   helm_release_name = "jenkins"
#   helm_release_chart = "jenkins"
#
#   parameters = {
#     jenkins_hostname    = "traefik.jenkins.local.com"
#     jenkins_url         = "http://traefik.jenkins.local.com/"
#     jenkins_volume_size = "100Gi"
#     jenkins_username    = dependency.vault-secrets.outputs.jenkins_secrets["username"]
#     jenkins_password    = dependency.vault-secrets.outputs.jenkins_secrets["password"]
#   }
#
#   jenkins_plugins = {
#     kubernetes                             = "4295.v7fa_01b_309c95"
#     workflow-aggregator                    = "600.vb_57cdd26fdd7"
#     git                                    = "5.5.2"
#     github                                 = "1.40.0"
#     configuration-as-code                  = "1850.va_a_8c31d3158b_"
#     blueocean-bitbucket-pipeline           = "1.27.16"
#     bitbucket-push-and-pull-request        = "3.1.1"
#     atlassian-bitbucket-server-integration = "4.1.0"
#     parameterized-scheduler                = "277.v61a_4b_a_49a_c5c"
#     github-checks                          = "589.v845136f916cd"
#     thinBackup                             = "2.1.1"
#     git-parameter                          = "0.9.19"
#     hashicorp-vault-plugin                 = "371.v884a_4dd60fb_6"
#   }
# }
