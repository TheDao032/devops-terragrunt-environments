locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../terraform-modules//on-prem/core-dns"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
}

# dependency "vault-secrets" {
#   config_path = "../vault-secrets"
#   mock_outputs = {
#     grafana_secrets = {
#       "grafana/creds" = {
#         username = "value"
#         password = "value"
#       }
#     }
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }

include {
  path = find_in_parent_folders()
}

inputs = {
  chart_version      = "1.10.101-build2021022303"
  namespace          = "kube-system"
  helm_repository    = "https://rke2-charts.rancher.io/"
  helm_release_name  = "coredns"
  helm_release_chart = "rke2-coredns"
}
