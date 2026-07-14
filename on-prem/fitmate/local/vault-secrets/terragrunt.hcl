locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/vault-secrets"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/shared/vault-secrets?ref=${local.environment}"
}

dependency "vault-auth" {
  config_path = "../vault-auth"
  mock_outputs = {
    kv_mount_path = "string"
    roles = {
      admin = {
        client_token = "string",
        role_id      = "string",
        secret_id    = "string"
      }
      dev = {
        client_token = "string",
        role_id      = "string",
        secret_id    = "string"
      }
      operator = {
        client_token = "string",
        role_id      = "string",
        secret_id    = "string"
      }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  # Overrides variables from env.hcl
  kv_mount_path = dependency.vault-auth.outputs.kv_mount_path
  secrets = merge(
    local.environment_vars.locals.secrets,
    {
      for role, creds in dependency.vault-auth.outputs.roles :
      "vault/approle/${role}/creds" => {
        client_token = creds.client_token,
        role_id      = creds.role_id,
        secret_id    = creds.secret_id
      }
    }
  )
}
