# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  hostname        = "app.terraform.io"
  organization    = "nthedao_org"
  workspaces_name = "nthedao_ws"

  docker_registry = get_env("DOCKER_REGISTRY", "https://index.docker.io/v1/")
  docker_token    = get_env("DOCKER_TOKEN", "")
  docker_username = get_env("DOCKER_USERNAME", "nthedao")
  docker_email    = get_env("DOCKER_EMAIL", "nthedao2705@gmail.com")

  github_token    = get_env("GITHUB_TOKEN", "")
  github_username = get_env("GITHUB_USERNAME", "TheDao032")

  gitops_url           = "git@github.com:${local.github_username}"
  ssh_private_key      = get_env("SSH_PRIVATE_KEY", "")

  artifactory_registry = get_env("ARTIFACTORY_REGISTRY", "nthedao")
}
