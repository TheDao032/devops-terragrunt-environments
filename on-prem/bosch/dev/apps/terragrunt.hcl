locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  # source = "../../../../../devops-terraform-modules//on-prem/apps"
  source = "../../../../../devops-terraform-modules//on-prem/apps"
}

dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    secrets = {
      "docker/creds" = {
        username = "value"
      }

      "github/params" = {
        repo_url = "values"
      }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "k3s-addons" {
  config_path = "../k3s"
  mock_outputs = {
    argocd_namespace = "values"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "external-secrets" {
  config_path = "../external-secrets"
  mock_outputs = {
    local_backend_name  = "values"
    gitops_backend_name = "values"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  pod_restart_collector = {
    secret = {
      store_name = dependency.external-secrets.outputs.local_backend_name
      name       = "pod-res-col-ex-secret"
    }

    docker = {
      secret_name  = "docker-ex-token"
      organization = dependency.vault-secrets.outputs.secrets["docker/creds"]["username"]
    }

    argocd = {
      namespace = dependency.k3s-addons.outputs.argocd_namespace
    }

    github = {
      secret_name = "github-ex-ssh-priv-key"
      url         = dependency.vault-secrets.outputs.secrets["github/params"]["url"]
      gitops_repo = dependency.vault-secrets.outputs.secrets["github/params"]["gitops_repo"]
    }

    common = {
      app_name  = "pod-restart-collector"
      namespace = local.environment
    }
  }
}
