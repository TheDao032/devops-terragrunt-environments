locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../terraform-modules//on-prem/"
}

dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    grafana_secrets = {
      "grafana/creds" = {
        username = "value"
        password = "value"
      }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  chart_version      = "24.2.2"
  namespace          = "default"
  helm_repository    = "https://charts.bitnami.com/bitnami"
  helm_release_name  = "keycloak"
  helm_release_chart = "bitnami-keycloak"

  keycloak_conf = {
    ingress = {
      host         = "nthedao.info"
      prefix       = "/"
      prefix_type  = "Prefix"
      strip_prefix = "keycloak-strip-prefix"
    }

    resources = {
      rq_mem     = "128Mi"
      rq_cpu     = "1"
      limits_mem = "256Mi"
      limits_cpu = "2"
    }
  }
}
