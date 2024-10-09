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

  prometheus_ingress = {
    host = "traefik.prometheus.local.com"
    prefix = "/"
  }

  alertmanager_ingress = {
    host = "traefik.alertmanager.local.com"
    prefix = "/"
  }

  grafana_ingress = {
    host = "traefik.grafana.local.com"
    prefix = "/"
  }
}
