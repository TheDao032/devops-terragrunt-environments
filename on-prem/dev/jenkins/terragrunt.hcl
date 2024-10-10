locals {
}

terraform {
  source = "../../../../terraform-modules//on-prem/jenkins"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  chart_version = "5.7.3"
  jenkins_image_tag = "2.479-jdk17"

  parameters = {
    jenkins_hostname = "traefik.jenkins.local.com"
    jenkins_url      = "http://traefik.jenkins.local.com/"
    jenkins_username = "admin"
    jenkins_password = "admin"
  }

  jenkins_plugins = {
    parameterized-scheduler = "262.v00f3d90585cc"
    github-checks           = "554.vb_ee03a_000f65"
    thinBackup              = "1.19"
    git-parameter           = "0.9.19"
  }
}
