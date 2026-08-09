locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/service-accounts"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/shared/service-accounts?ref=${local.environment}"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "kube" {
  path = find_in_parent_folders("kube.hcl")
}

dependency "init-resources" {
  config_path = "../init-resources"

  mock_outputs = {
    init-resources_output = "mock-init-resources-output"
  }

  # mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  # Overrides variables from env.hcl
  rbacs = {
    traefik = {
      sa = {
        metadata = {
          name      = "traefik"
          namespace = "kube-system"

        }
      }
      cluster_role = {
        metadata = {
          name = "traefik-manager"
        }
        rule = {
          api_groups = ["traefik.containo.us"]
          resources  = ["middlewares"]
          verbs      = ["get", "list", "watch", "create", "update", "delete"]
        }
      }
      cluster_role_binding = {
        metadata = {
          name = "traefik-manager-binding"
        }
      }
    }
  }
}
