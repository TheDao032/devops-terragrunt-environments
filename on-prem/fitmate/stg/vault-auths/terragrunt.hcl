locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  # Env-suffix convention: prod is the canonical env (BARE, no suffix); dev/stg are suffixed.
  # Mirrors k8s_auth_path (kubernetes vs kubernetes-<env>) + realm_name (fitmate vs fitmate-<env>).
  # → ns/role: fitmate-<svc>(-eso) for prod, fitmate-<svc>-<env>(-eso) for dev/stg.
  env_suffix = local.environment == "prod" ? "" : "-${local.environment}"

  # Org mount ("fitmate") is created ONCE by shared/vault-auths (mount_kv=true). This per-env unit
  # only adds its own folder ("<env>/") + per-app roles inside the shared mount.
  org_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org      = local.org_vars.locals.infras_organization

  # Per-app ESO services (ADR-036). Each entry → a `fitmate-<svc>[-<env>]-eso` k8s-auth role bound to
  # (ns fitmate-<svc>[-<env>], SA <sa>), read-scoped to fitmate/data/<env>/<svc>/* (its own subtree)
  # plus read on the shared platform/kafka + platform/redis creds. Add a service = add a line.
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
}

# ── Bootstrap gate ── skip until Vault is up + unsealed (shared init-resources deploys it).
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

# Ordering-only edge: the org KV mount ("fitmate") is created by shared/vault-auths (mount_kv=true).
# This per-env unit (mount_kv=false) must run AFTER it so the mount exists. No outputs are consumed —
# the mount path is derived from `org`, not fetched — so `dependencies` (plural, run-order only).
dependencies {
  paths = ["../../shared/vault-auths"]
}

inputs = {
  environment = local.environment # → path_prefix "<env>/" (folder inside the shared org mount)
  org         = local.org         # existing org mount ("fitmate")
  mount_kv    = false             # shared/vault-auths owns the mount — this env does NOT re-mount

  # Per-env Kubernetes auth backend path. Vault has ONE mount per path, so each env MUST own a
  # distinct one (kubernetes-dev/stg/prod) or they collide: "path is already in use at kubernetes/".
  # ESO SecretStores set auth.kubernetes.mountPath to this (flows via the k8s_auth_mount output).
  k8s_auth_path = local.environment == "prod" ? "kubernetes" : "kubernetes-${local.environment}"

  # No AppRoles here — admin + external-secrets AppRoles are platform (shared/vault-auths).
  roles = {}

  # Per-app ESO SecretStore roles. Each app authenticates with its own ServiceAccount JWT and gets a
  # read-only token scoped to ITS OWN subtree (fitmate/data/<env>/<svc>/*) + the shared infra creds
  # (platform/kafka, platform/redis). App namespaces: fitmate-<svc> (prod) / fitmate-<svc>-<env> (dev,stg).
  k8s_auth = {
    for svc, sa in local.eso_service_sa : "fitmate-${svc}${local.env_suffix}-eso" => {
      namespaces       = ["fitmate-${svc}${local.env_suffix}"]
      service_accounts = [sa]
      policies = [
        {
          path                  = "${svc}/*" # → fitmate/data/<env>/<svc>/*
          data_capabilities     = "read"
          metadata_capabilities = "read,list"
          delete_capabilities   = "deny"
          destroy_capabilities  = "deny"
        },
        {
          path                  = "platform/kafka/*" # shared Kafka SASL creds
          data_capabilities     = "read"
          metadata_capabilities = "read,list"
          delete_capabilities   = "deny"
          destroy_capabilities  = "deny"
          absolute              = true # cross-tier: fitmate/data/platform/kafka/* (NOT env-prefixed)
        },
        {
          path                  = "platform/redis/*" # shared Redis auth
          data_capabilities     = "read"
          metadata_capabilities = "read,list"
          delete_capabilities   = "deny"
          destroy_capabilities  = "deny"
          absolute              = true # cross-tier: fitmate/data/platform/redis/* (NOT env-prefixed)
        }
      ]
    }
  }

  # No Vault userpass users here — the platform admin lives in shared/vault-auths.
  users = {}
}
