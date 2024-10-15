locals {
}

terraform {
  source = "../../../../terraform-modules//on-prem/prometheus"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
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

  prometheus_ingress = {
    host = "traefik.prometheus.local.com"
    prefix = "/"
    prefix_type = "Prefix"
  }

  alertmanager_ingress = {
    host = "traefik.alertmanager.local.com"
    prefix = "/"
    prefix_type = "Prefix"
  }

  grafana_ingress = {
    host = "traefik.grafana.local.com"
    prefix = "/"
    prefix_type = "Prefix"
  }
}
