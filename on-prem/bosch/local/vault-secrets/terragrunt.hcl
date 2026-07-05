locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  # source = "../../../../../devops-terraform-modules//on-prem/vault-secrets"
  source = "../../../../../devops-terraform-modules//on-prem/vault-secrets"
}

dependency "vault-roles" {
  config_path = "../vault-roles"
  mock_outputs = {
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
  secrets = merge(
    local.environment_vars.locals.secrets,
    {
      for role, creds in dependency.vault-roles.outputs.roles :
      "vault/approle/${role}/creds" => {
        client_token = creds.client_token,
        role_id      = creds.role_id,
        secret_id    = creds.secret_id
      }
    }
  )
}
