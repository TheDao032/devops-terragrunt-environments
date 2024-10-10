locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  secrets          = local.environment_vars.locals.secrets
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
    jenkins_username = local.secrets.jenkinsUsername
    jenkins_password = local.secrets.jenkinsPassword
  }

  jenkins_plugins = {
    blueocean-bitbucket-pipeline           = "1.27.16"
    bitbucket-push-and-pull-request        = "3.1.1"
    atlassian-bitbucket-server-integration = "4.1.0"
    parameterized-scheduler                = "277.v61a_4b_a_49a_c5c"
    github-checks                          = "589.v845136f916cd"
    thinBackup                             = "2.1.1"
    git-parameter                          = "0.9.19"
  }
}
