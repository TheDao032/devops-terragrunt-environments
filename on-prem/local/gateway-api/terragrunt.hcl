locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../terraform-modules//on-prem/gateway-api"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
}

# dependency "vault-secrets" {
#   config_path = "../vault-secrets"
#   mock_outputs = {
#     secrets = {
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

  nginx_gateway_fabric = {
    helm_chart = {
      chart_version      = "1.6.2"
      namespace          = "nginx-gateway"
      helm_repository    = "oci://ghcr.io/nginx/charts/nginx-gateway-fabric"
      helm_release_name  = "ngf"
      helm_release_chart = "nginx-gateway-fabric"
    }

    image = {
      tag = "nthedao.info"
    }
  }

  traefik_gateway_api = {
  }
}
