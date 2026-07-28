locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  # source = "../../../../../devops-terraform-modules//on-prem/shared/vault-auths"
  source = "../../../../../devops-terraform-modules//on-prem/shared/vault-auths"
}

# dependency "vault-secrets" {
#   config_path = "../vault-secrets"
#   mock_outputs = {
#     vault_mount_path = "values"
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }

include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  # Overrides variables from env.hcl
  # vault_mount_path = dependency.vault-secrets.outputs.vault_mount_path
  roles = {
    admin = [
      {
        path                  = "*"
        data_capabilities     = "create,read,update,delete,list"
        metadata_capabilities = "create,read,update,delete,list"
        delete_capabilities   = "create,read,update,delete,list"
        destroy_capabilities  = "create,read,update,delete,list"
      }
    ]
    dev = [
      {
        path                  = "jenkins/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "Database/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "agile/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "hikari/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "authHeader/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "queryService/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      }
    ]
    operation = [
      {
        path                  = "*"
        data_capabilities     = "create,read,update,delete,list"
        metadata_capabilities = "create,read,update,delete,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      }
    ]
    jenkins_app = [
      {
        path                  = "Database/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "agile/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "hikari/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "authHeader/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "queryService/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
      {
        path                  = "k3s/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      }
    ]
  }
}
