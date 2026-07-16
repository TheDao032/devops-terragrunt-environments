# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  # vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault.hcl"))
  # vault_address     = local.vault_config_vars.locals.address
  # vault_token       = local.vault_config_vars.locals.token

  backend_vars            = read_terragrunt_config(find_in_parent_folders("backend.hcl"))
  backend_docker_registry = local.backend_vars.locals.docker_registry
  backend_docker_username = local.backend_vars.locals.docker_username
  backend_docker_token    = local.backend_vars.locals.docker_token
  backend_docker_email    = local.backend_vars.locals.docker_email

  backend_gitops_url   = local.backend_vars.locals.gitops_url
  backend_ssh_priv_key = local.backend_vars.locals.ssh_private_key

  backend_github_token    = local.backend_vars.locals.github_token
  backend_github_username = local.backend_vars.locals.github_username

  backend_artifactory_registry = local.backend_vars.locals.artifactory_registry

  org_vars       = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org_infras_org = local.org_vars.locals.infras_organization

  environment  = "local"
  cluster_name = "local"

  secrets = {
    "artifactory/params" = {
      registry = local.backend_artifactory_registry
    }

    "docker/creds" = {
      username = local.backend_docker_username
      password = local.backend_docker_token
      email    = local.backend_docker_email
    }

    "docker/params" = {
      registry = local.backend_docker_registry
    }

    "github/params" = {
      url         = local.backend_gitops_url
      gitops_repo = "gitops-apps"
      insecure    = "false"
      enablelfs   = "false"
    }

    "github/creds" = {
      ssh_priv_key = local.backend_ssh_priv_key
      username     = local.backend_github_username
      token        = local.backend_github_token
    }

    "argocd/params" = {
    }

    "argocd/creds" = {
      username = "admin"
      password = "{ _RANDOM_ = 18 }"
    }

    # "jenkins/creds" = {
    #   username = "admin"
    #   password = "{ _RANDOM_ = 18 }"
    # }
    #
    # "grafana/creds" = {
    #   username = "admin"
    #   password = "{ _RANDOM_ = 18 }"
    # }
    #
    # "loki/creds" = {
    #   username = "admin"
    #   password = "{ _RANDOM_ = 18 }"
    # }
    #
    # "kafka/creds" = {
    #   clientUsername = "admin"
    #   clientPassword = "{ _RANDOM_ = 18 }"
    # }

    # Commented until Vault is deployed + initialized — vault_address / vault_token
    # come from vault.hcl (uncommented above at that stage).
    # "vault/params" = {
    #   clusterAddr = local.vault_address
    # }
    #
    # "vault/creds" = {
    #   rootToken = local.vault_token
    # }

    # "database/params" = {
    #   DBClusterEndpoint = get_env("DB_CLUSTER_ENDPOINT", "192.168.56.31")
    #   DBClusterPort     = 5432
    # }
    #
    # "database/admin-service/creds" = {
    #   username = "fiesta"
    #   password = "{ _RANDOM_ = 18 }"
    #   database = "fiesta"
    # }

    # "podRestartCollector/creds" = {
    #   slackWebhookUrl = get_env("SLACK_WEBHOOK_URL", "")
    # }
  }

  # cloudflare_api_token = get_env("CLOUDFLARE_API_TOKEN", "")

  tags = {
    created_by    = "terraform"
    environment   = local.environment
    organiazation = local.org_infras_org
  }


}
