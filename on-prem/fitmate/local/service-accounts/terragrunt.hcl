locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/service-accounts"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/shared/service-accounts?ref=${local.environment}"
}

include {
  path = find_in_parent_folders("root.hcl")
}

include "vault" {
  path = find_in_parent_folders("vault-config.hcl")
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
