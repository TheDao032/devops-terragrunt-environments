locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/vault-secrets"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/shared/vault-secrets?ref=${local.environment}"
}

# ── Bootstrap gate ────────────────────────────────────────────────────────────
# Skip until Vault is genuinely up+unsealed. Gate on ACTUAL reachability via the health
# endpoint (a stale VAULT_TOKEN hardcoded in .envrc.local makes a token-presence gate
# useless): `curl -f` fails while Vault is down/sealed/uninitialized → exclude; 200 →
# include. `run --all` picks this unit up automatically once Vault is live. See on-prem/vault.hcl.
exclude {
  if = run_cmd("--terragrunt-quiet", "bash", "-c",
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.dev}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

dependency "vault-auths" {
  config_path = "../vault-auths"
  mock_outputs = {
    kv_mount_path      = "string"
    secret_path_prefix = "string"
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

include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  # Overrides variables from env.hcl
  kv_mount_path = dependency.vault-auths.outputs.kv_mount_path
  path_prefix   = dependency.vault-auths.outputs.secret_path_prefix # "local/" — env folder inside the mount
  secrets = merge(
    local.environment_vars.locals.secrets,
    {
      for role, creds in dependency.vault-auths.outputs.roles :
      "vault/approle/${role}/creds" => {
        client_token = creds.client_token,
        role_id      = creds.role_id,
        secret_id    = creds.secret_id
      }
    }
  )

  # Pre-hash selected passwords into stable siblings (chart fields wanting a hash, not plaintext).
  password_hashes = {
    "argocd/creds" = { algo = "bcrypt" } # → adds argocd/creds.password_bcrypt (random_password.bcrypt_hash)
  }
}
