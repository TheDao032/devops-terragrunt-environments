locals {
}

terraform {
  source = "../../../../terraform-modules//on-prem/prometheus"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
}

dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    grafana_secrets = {
      "grafana/creds": {
        username = "value"
        password = "value"
      }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  chart_version = "65.1.0"
  namespace = "monitoring"
  helm_repository = "https://prometheus-community.github.io/helm-charts"
  helm_release_name = "prometheus"
  helm_release_chart = "kube-prometheus-stack"

  prometheus = {
    ingress = {
      host = "nthedao.info"
      prefix = "/prometheus"
      prefix_type = "Prefix"
    }
  }

  alertmanager = {
    ingress = {
      host = "nthedao.info"
      prefix = "/alertmanager"
      prefix_type = "Prefix"
    }
  }

  grafana = {
    ingress = {
      host = "nthedao.info"
      prefix = "/grafana"
      prefix_type = "Prefix"
    }

    auth = {
      username = dependency.vault-secrets.outputs.grafana_secrets["grafana/creds"]["username"]
      password = dependency.vault-secrets.outputs.grafana_secrets["grafana/creds"]["password"]
    }
  }
}
