locals {
}

terraform {
  source = "../../../../terraform-modules//on-prem/prometheus"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
}

dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    output = {
      key = "value"
    }
    # public_subnets = ["name1","name2"]
    # private_subnets = ["name1","name2"]
    # eks_securitygroup = "eks_security_group"
    # eks_node_securitygroup = "eks_node_security_group"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  chart_version = "65.1.0"
  namespace = "monitoring"
  helm_repository = "https://prometheus-community.github.io/helm-charts"
  helm_release_name = "prometheus-community"
  helm_release_chart = "kube-prometheus-stack"

  secrets = dependency.vault-secrets.outputs.output

  prometheus = {
    ingress = {
      host = "traefik.prometheus.local.com"
      prefix = "/"
      prefix_type = "Prefix"
    }
  }

  alertmanager = {
    ingress = {
      host = "traefik.alertmanager.local.com"
      prefix = "/"
      prefix_type = "Prefix"
    }
  }

  grafana = {
    ingress = {
      host = "traefik.grafana.local.com"
      prefix = "/"
      prefix_type = "Prefix"
    }

    auth = {
      username = dependency.vault-secrets.outputs.output["grafanaUsername"]
      password = dependency.vault-secrets.outputs.output["grafanaPassword"]
    }
  }
}