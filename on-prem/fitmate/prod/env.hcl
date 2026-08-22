# PER-ENV (stg) tier — one of dev/stg/prod on the shared fitmate k3s cluster.
#
# `secrets` here = APP-level secrets only, seeded into the shared Vault KV at fitmate/data/<env>/*
# (path_prefix "<env>/"). PLATFORM secrets (docker/github/argocd/kafka/redis/keycloak-admin) live in
# shared/env.hcl → fitmate/data/platform/*. DB + role names are env-suffixed (<svc>_<env>) so one PG
# server can host dev/stg/prod side by side. App namespaces: fitmate-<svc> (prod) / fitmate-<svc>-<env> (dev,stg).
locals {
  # Only the GitHub token is needed here (per-app GHCR image-pull creds). Other backend platform
  # values (docker/gitops/artifactory) are consumed by shared/, not per env.
  backend_vars            = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  backend_github_username = local.backend_vars.locals.github_username
  backend_github_token    = local.backend_vars.locals.github_token

  org_vars       = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org_infras_org = local.org_vars.locals.infras_organization

  environment  = "prod"
  cluster_name = "fitmate"

  # Cloudflare API token for THIS env's edge units (cloudflare-tunnel / cloudflare-access, read as
  # local.environment_vars.locals.cloudflare_api_token). From the CLOUDFLARE_API_TOKEN env
  # (.envrc.local / deploy-env.bash).
  # NOTE (2026-08-22, IN-15): prod is NO LONGER the only tier carrying an edge stack — dev and stg
  # now own their own tunnel + connector so each env's Keycloak hostname stamps its own `iss`.
  # This local is therefore present in all three env.hcl files, not just here.
  cloudflare_api_token = get_env("CLOUDFLARE_API_TOKEN", "")

  # Realm name for this env on the shared Keycloak (matches keycloak/fitmate unit): fitmate-<env>,
  # or plain `fitmate` for prod. Used to build the per-service token issuer/JWKS URLs below.
  realm_name = local.environment == "prod" ? "fitmate" : "fitmate-${local.environment}"

  # Browser-facing issuer host (must equal token `iss`). prod is exposed publicly via Cloudflare
  # (auth.fitmate.me); dev/stg use the in-cluster Traefik host. JWKS always uses the in-cluster
  # Service URL (pods can't resolve the ingress host).
  issuer_host = local.environment == "prod" ? "https://auth.fitmate.me" : "http://keycloak.k3s.fitmate"

  secrets = {
    # ── Per-app GHCR image-pull creds (value = the GitHub read:packages PAT). Per-env folder so each
    #    app's fitmate-<svc>-<env>-eso role can read its own copy. Add a line per image-pulling app.
    "trainee/ghcr-pull" = { username = local.backend_github_username, token = local.backend_github_token }
    "website/ghcr-pull" = { username = local.backend_github_username, token = local.backend_github_token }

    # ── PostgreSQL superuser (tf_admin) — ONE PG server backs all envs, so this is the same stable
    #    value everywhere (also in shared/env.hcl for the keycloak DB). Read by this env's database units.
    "database/superuser/creds" = {
      username = "tf_admin"
      password = get_env("PG_ADMIN_PASSWORD", "change-me-tf-admin")
    }

    # ── Per-env app DB roles. Usernames are env-suffixed to match the database units' role names
    #    (separate DB per env: <svc>_<env> databases owned by <svc>_app_<env>). Passwords → Vault.
    "database/trainee/app/creds" = { username = "trainee_app_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    "database/trainee/ro/creds"  = { username = "trainee_ro_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    "database/trainer/app/creds" = { username = "trainer_app_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    "database/trainer/ro/creds"  = { username = "trainer_ro_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    "database/booking/app/creds" = { username = "booking_app_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    "database/booking/ro/creds"  = { username = "booking_ro_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    "database/inquiry/app/creds" = { username = "inquiry_app_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    "database/inquiry/ro/creds"  = { username = "inquiry_ro_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    "database/admin/app/creds"   = { username = "admin_app_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    "database/admin/ro/creds"    = { username = "admin_ro_${local.environment}", password = "{ _RANDOM_ = 18 }" }
    # payment — WRITE-ONLY today (gateway unbuilt) → app role only, no ro.
    "database/payment/app/creds" = { username = "payment_app_${local.environment}", password = "{ _RANDOM_ = 18 }" }

    # ── Keycloak realm seed user (per-env realm) — e2e password-grant fixture.
    "keycloak/fitmate/trainee1/creds" = { username = "trainee1", password = "{ _RANDOM_ = 16 }" }

    # ── Per-service Keycloak token-validation config (NON-secret; issuer/audience/JWKS). ESO syncs
    #    each <svc>/params into a <svc>-keycloak Secret the service reads. ISSUER = the browser-facing
    #    host (must equal token `iss`); JWKSURL = the in-cluster Service (pods can't resolve the host).
    #    Realm is per-env (local.realm_name). MVP: only trainee migrated; fan out per service in Phase 2.
    "trainee/params" = {
      KEYCLOAK_ISSUER   = "${local.issuer_host}/realms/${local.realm_name}"
      KEYCLOAK_AUDIENCE = "fitmate-backend"
      KEYCLOAK_JWKSURL  = "http://keycloak-service.keycloak.svc.cluster.local:8080/realms/${local.realm_name}/protocol/openid-connect/certs"
    }
  }

  tags = {
    created_by   = "terraform"
    environment  = local.environment
    organization = local.org_infras_org
  }
}
