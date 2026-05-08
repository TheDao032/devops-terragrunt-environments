locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/helm/charts/prometheus"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
}

dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    secrets = {
      "grafana/creds" = {
        username = "value"
        password = "value"
      }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "loki" {
  config_path = "../loki"
  mock_outputs = {
    internal_loki_server = "value"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  chart_version        = "65.1.0"
  namespace            = "monitoring"
  helm_repository      = "https://prometheus-community.github.io/helm-charts"
  helm_release_name    = "prometheus"
  helm_release_chart   = "kube-prometheus-stack"
  internal_loki_server = dependency.loki.outputs.internal_loki_server

  prometheus = {
    ingress = {
      host         = "nthedao.info"
      prefix       = "/"
      prefix_type  = "Prefix"
      strip_prefix = "prometheus-strip-prefix"
    }
  }

  alertmanager = {
    ingress = {
      host         = "nthedao.info"
      prefix       = "/alertmanager"
      prefix_type  = "Prefix"
      strip_prefix = "alertmanager-strip-prefix"
    }
  }

  grafana = {
    ingress = {
      host         = "nthedao.info"
      prefix       = "/grafana"
      prefix_type  = "Prefix"
      strip_prefix = "grafana-strip-prefix"
    }

    auth = {
      username = dependency.vault-secrets.outputs.secrets["grafana/creds"]["username"]
      password = dependency.vault-secrets.outputs.secrets["grafana/creds"]["password"]
    }
  }
}
