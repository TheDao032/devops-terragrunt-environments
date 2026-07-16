locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/vault-auth"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/shared/vault-auth?ref=${local.environment}"
}

# root.hcl → kube providers + backend. vault-config.hcl → the vault provider (address/token
# from VAULT_ADDR/VAULT_TOKEN env, empty defaults). Only vault stacks include vault-config.hcl,
# so non-vault stacks never get a vault provider.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "vault" {
  path = find_in_parent_folders("vault-config.hcl")
}

inputs = {
  environment = local.environment
  mount_kv    = true # this stack owns the KV-v2 engine at path "${local.environment}"

  # Policies (same shape as vault-roles). admin = full control of every KV path; dev = scoped.
  roles = {
    admin = [
      {
        path                  = "*"
        data_capabilities     = "create,read,update,delete,list"
        metadata_capabilities = "create,read,update,delete,list"
        delete_capabilities   = "create,read,update,delete,list"
        destroy_capabilities  = "create,read,update,delete,list"
      },
    ]
    dev = [
      {
        path                  = "dev/*"
        data_capabilities     = "create,read,update,list"
        metadata_capabilities = "create,read,update,list"
        delete_capabilities   = "create,read,update,list"
        destroy_capabilities  = "create,read,update,list"
      },
    ]
    external-secrets = [
      {
        path                  = "*"         # → local/data/* , local/metadata/* , ...
        data_capabilities     = "read"      # ESO reads secret values
        metadata_capabilities = "read,list" # needed for property/find lookups
        delete_capabilities   = "deny"      # explicit deny (empty string = invalid policy)
        destroy_capabilities  = "deny"
      }
    ]
  }

  # Users. Passwords come from the ENV so nothing secret is in the repo/state-as-plaintext.
  # Before apply:  export VAULT_ADMIN_PASSWORD=...  VAULT_DEV_PASSWORD=...
  users = {
    dao = {
      password = "{ _RANDOM_ = 18 }"
      policies = ["admin"]
    }
    dev = {
      password = "{ _RANDOM_ = 18 }"
      policies = ["dev"]
    }
  }
}
