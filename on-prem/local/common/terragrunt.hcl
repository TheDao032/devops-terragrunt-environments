locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  # secrets          = local.environment_vars.locals.secrets
}

terraform {
  source = "../../../../terraform-modules//on-prem/common"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
}

# dependency "vault-secrets" {
#   config_path = "../vault-secrets"
#   mock_outputs = {
#     secrets = {
#       "jenkins/creds" = {
#         username = "value"
#         password = "value"
#       }
#
#       # "argocd/creds" = {
#       #   username = "value"
#       #   password = "value"
#       # }
#     }
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }

include {
  path = find_in_parent_folders()
}

inputs = {
  traefik_conf = {
    namespace = "kube-system"
  }
}
