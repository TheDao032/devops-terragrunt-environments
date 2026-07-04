locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  # source = "../../../../../devops-terraform-modules//on-prem/vault-roles"
  source = "../../../../../devops-terraform-modules//on-prem/vault-roles"
}

# dependency "vault-secrets" {
#   config_path = "../vault-secrets"
#   mock_outputs = {
#     vault_mount_path = "values"
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }

include {
  path = find_in_parent_folders()
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
        path                  = "database/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
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
    ]
  }
}
