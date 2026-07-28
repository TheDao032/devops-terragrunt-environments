locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  # Org/tenant → roots the KV mount + policy paths at "<org>/<env>" (e.g. fitmate/local).
  org_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org      = local.org_vars.locals.infras_organization
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/vault-auths"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/shared/vault-auths?ref=${local.environment}"
}

# ── Bootstrap gate ────────────────────────────────────────────────────────────
# Vault config can't plan until Vault is deployed (init-resources) AND initialized+
# unsealed — the vault provider does an eager token lookup-self that fails with
# "connection refused" while Vault is down. Gate on ACTUAL reachability via the health
# endpoint (a stale VAULT_TOKEN is hardcoded in .envrc.local, so a token-presence gate
# is useless): `curl -f` fails on connection-refused / 503-sealed / 501-uninitialized
# → exclude; 200-active → include. So `run --all` skips these units until Vault is
# genuinely up+unsealed, then picks them up automatically. Nothing outside the vault
# units (vault-auths/vault-secrets/ops-tools) depends on them, so no dangling dependency.
# ($${...} escapes to a literal ${...} for the shell; run_cmd result is cached across units.)
exclude {
  if = run_cmd("--terragrunt-quiet", "bash", "-c",
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.local}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

# root.hcl → kube providers + backend. vault.hcl → the vault provider (address/token
# from VAULT_ADDR/VAULT_TOKEN env, empty defaults). Only vault stacks include vault.hcl,
# so non-vault stacks never get a vault provider.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "vault" {
  path = find_in_parent_folders("vault.hcl")
}

dependency "init-resources" {
  config_path = "../init-resources"

  mock_outputs = {
    init-resources_output = "mock-init-resources-output"
  }

  # mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  environment = local.environment
  org         = local.org # KV mount + policy paths become "<org>/<env>" = "${local.org}/${local.environment}"
  mount_kv    = true      # this stack owns the KV-v2 engine at path "${local.org}/${local.environment}"

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
        path                  = "*"         # → fitmate/local/data/* , fitmate/local/metadata/* , ...
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
