locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/vault-secrets"
}

# ── Bootstrap gate ── skip until Vault is up + unsealed (health endpoint).
exclude {
  if = run_cmd("--terragrunt-quiet", "bash", "-c",
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.fitmate}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

dependency "vault-auths" {
  config_path = "../vault-auths"
  mock_outputs = {
    kv_mount_path      = "string"
    secret_path_prefix = "string"
    roles = {
      admin            = { client_token = "string", role_id = "string", secret_id = "string" }
      external-secrets = { client_token = "string", role_id = "string", secret_id = "string" }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "vault" {
  path = find_in_parent_folders("vault.hcl")
}

inputs = {
  kv_mount_path = dependency.vault-auths.outputs.kv_mount_path
  path_prefix   = dependency.vault-auths.outputs.secret_path_prefix # "platform/" — platform folder in the org mount
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

  # ArgoCD wants a bcrypt hash of its admin password (chart field), not plaintext.
  password_hashes = {
    "argocd/creds" = { algo = "bcrypt" } # → adds argocd/creds.password_bcrypt (random_password.bcrypt_hash)
  }
}
