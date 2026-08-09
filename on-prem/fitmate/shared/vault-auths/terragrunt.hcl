locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Org/tenant → roots the ONE org-level KV mount ("fitmate"). This SHARED unit is the sole owner
  # of the mount (mount_kv = true). Each env's vault-auths sets mount_kv = false and only adds its
  # own per-app roles + policies inside per-env folders (fitmate/data/<env>/*).
  org_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org      = local.org_vars.locals.infras_organization

  # Platform secrets live under the "platform/" folder inside the org mount → fitmate/data/platform/*.
  kv_folder = "platform"
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/vault-auths"
}

# ── Bootstrap gate ── skip until Vault (init-resources) is up + unsealed (health endpoint).
exclude {
  if = run_cmd("--terragrunt-quiet", "bash", "-c",
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.fitmate}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "vault" {
  path = find_in_parent_folders("vault.hcl")
}

inputs = {
  environment = local.kv_folder # → path_prefix "platform/" (folder inside the org mount)
  org         = local.org       # KV mount path = the org itself ("fitmate")
  mount_kv    = true            # THIS unit owns the org KV-v2 engine (the only mount_kv=true)

  # Policies. admin = full control of every KV path (all envs + platform). external-secrets = the
  # PLATFORM ESO SecretStore identity (ArgoCD reads platform creds) — read-only across the mount.
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
    external-secrets = [
      {
        path                  = "*" # read the whole org mount (platform + envs) for the ArgoCD store
        data_capabilities     = "read"
        metadata_capabilities = "read,list"
        delete_capabilities   = "deny"
        destroy_capabilities  = "deny"
      }
    ]
  }

  # No k8s-auth here — per-app ESO SecretStore roles are PER-ENV (each env's vault-auths binds
  # fitmate-<svc>-<env> → its own subtree). The platform ESO store uses the external-secrets AppRole.
  k8s_auth = {}

  # Platform admin (Vault userpass). Per-env human/dev users are not created here.
  users = {
    dao = {
      password = "{ _RANDOM_ = 18 }"
      policies = ["admin"]
    }
  }
}
