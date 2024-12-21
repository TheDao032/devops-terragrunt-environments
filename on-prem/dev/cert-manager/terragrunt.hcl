locals {
}

terraform {
  source = "../../../../terraform-modules//on-prem/cert-manager"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  chart_version = "1.16.1"
  namespace = "default"
  helm_repository = "https://charts.jetstack.io"
  helm_release_name = "cert-manager"
  helm_release_chart = "cert-manager"
  email = "nthedao2705@gmail.com"
}
