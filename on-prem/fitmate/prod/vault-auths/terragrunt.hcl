locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  # Org/tenant → roots the KV mount + policy paths at "<org>/<env>" (e.g. fitmate/local).
  org_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org      = local.org_vars.locals.infras_organization

  # Per-app ESO services (ADR-036) — the full FitMate stack (inventory confirmed by the fitmate agent
  # 2026-08-01). Each entry generates a `fitmate-<svc>-eso` k8s-auth role bound to (ns fitmate-<svc>,
  # SA <sa>), read-scoped to fitmate/data/local/<svc>/*. Key = service, value = its ServiceAccount
  # (= the workload release name). Add a service = add a line here. NOTE: only `trainee` is
  # Keycloak-migrated today; others still validate via SuperTokens (their secret DOC shape differs, but
  # the ESO ROLE is identical — read its own subtree — so all get a role now, ahead of app authoring).
  eso_service_sa = {
    "trainee"       = "trainee-service"
    "website"       = "website"
    "trainer"       = "trainer-service"
    "booking"       = "booking-service"
    "payment"       = "payment-service"
    "admin"         = "admin-service"
    "inquiry"       = "inquiry-service"
    "notification"  = "notification-service"
    "media"         = "media-service"
    "gateway"       = "api-gateway"
    "admin-website" = "admin-website"
  }
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
#
# SHARED-PLATFORM PROD (2026-08-02, [[production-cloudflare-tunnel]] Phase 1): prod reuses LOCAL's
# Vault (one Vault on the shared lab cluster) — it does NOT deploy its own. So the gate targets the
# EXISTING Vault (vault.k3s.local) and VAULT_ADDR must point there. init-resources is skipped (below).
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

# SHARED-PLATFORM PROD: init-resources (Vault deploy) is SKIPPED — prod reuses local's Vault. The
# module only uses init-resources as an ordering dep (no consumed outputs), so it's removed here to
# stop `run --all` from standing up a second Vault. Local still owns init-resources.
# dependency "init-resources" {
#   config_path  = "../init-resources"
#   mock_outputs = { init-resources_output = "mock-init-resources-output" }
# }

inputs = {
  environment = local.environment
  org         = local.org

  # ── SHARED-PLATFORM PROD ISOLATION (2026-08-02, [[production-cloudflare-tunnel]] Phase 1) ──
  # Prod shares LOCAL's single Vault on the lab cluster. To avoid colliding with local:
  #   • mount_kv=false → REUSE local's `fitmate` KV mount. Prod secrets live under the `prod/` folder
  #     (path_root=prod) → fitmate/data/prod/<svc>/*. (mount_kv=true would re-create the shared
  #     `fitmate` mount → "path already in use".)
  #   • roles={} + users={} → local already owns the admin/dev/external-secrets policies + the
  #     userpass backend/users; re-creating them collides. Prod's ESO policies come from k8s_auth below.
  #   • k8s_auth_path="kubernetes-prod" → prod owns its OWN k8s auth backend (local owns "kubernetes").
  mount_kv      = false
  roles         = {}
  users         = {}
  k8s_auth_path = "kubernetes-prod"

  # Kubernetes auth — per-app ESO SecretStores (ADR-036), PROD-SUFFIXED so nothing collides with
  # local's roles/namespaces on the shared cluster. One `fitmate-<svc>-prod-eso` role per service,
  # bound to (ns fitmate-<svc>-prod, SA <sa>), read-only on its OWN prod subtree fitmate/data/prod/<svc>/*.
  # Lives on the "kubernetes-prod" auth backend (k8s_auth_path above). FitMate's PROD SecretStores set
  # auth.kubernetes.role=fitmate-<svc>-prod-eso + auth.kubernetes.mountPath=kubernetes-prod.
  k8s_auth = {
    for svc, sa in local.eso_service_sa : "fitmate-${svc}-prod-eso" => {
      namespaces       = ["fitmate-${svc}-prod"]
      service_accounts = [sa]
      policies = [
        {
          path                  = "${svc}/*" # → fitmate/data/prod/<svc>/*
          data_capabilities     = "read"
          metadata_capabilities = "read,list"
          delete_capabilities   = "deny"
          destroy_capabilities  = "deny"
        }
      ]
    }
  }
  # (users = {} set above — prod reuses local's userpass users; no new users on the shared Vault.)
}
