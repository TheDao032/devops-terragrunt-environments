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

  environment  = "dev"
  cluster_name = "fitmate"

  # Cloudflare API token for THIS env's edge units (cloudflare-tunnel / cloudflare-access), read as
  # local.environment_vars.locals.cloudflare_api_token. From the CLOUDFLARE_API_TOKEN env var
  # (.envrc.local). Added 2026-08-22 (IN-15): each env now owns its OWN tunnel + connector, so the
  # edge stack is no longer prod-only. One tunnel per env keeps a leaked token scoped to that env's
  # hostnames, and avoids a shared tunnel whose single ingress resource can only have one owner.
  cloudflare_api_token = get_env("CLOUDFLARE_API_TOKEN", "")

  # Realm name for this env on the shared Keycloak (matches keycloak/fitmate unit): fitmate-<env>,
  # or plain `fitmate` for prod. Used to build the per-service token issuer/JWKS URLs below.
  realm_name = local.environment == "prod" ? "fitmate" : "fitmate-${local.environment}"

  # Browser-facing issuer host — must equal the token's `iss` claim EXACTLY (IN-16, ADR
  # 2026-08-23-public-host-is-canonical-token-issuer).
  #
  # Keycloak runs with hostname.strict=false, so it does NOT have one fixed issuer: it builds `iss`
  # from the request's X-Forwarded-Proto/Host. The issuer therefore follows whichever host minted
  # the token, and one Keycloak legitimately emits several:
  #     via Cloudflare        -> https://auth-<env>.fitmate.me/realms/<realm>
  #     via the cluster host  -> http://keycloak.k3s.fitmate/realms/<realm>
  #
  # Services compare `iss` with go-oidc's NewVerifier, which is a byte-for-byte string comparison —
  # no scheme tolerance, no host aliasing, a trailing slash is enough to fail. So a single expected
  # issuer is only correct if EVERY token for this env is minted through ONE host.
  #
  # That host must be the PUBLIC one, and this is forced rather than preferred: the website's Auth.js
  # provider discovers against this value and then REDIRECTS THE BROWSER to the authorization_endpoint
  # the discovery document returns. Discovery via the cluster host returns cluster URLs, so the browser
  # would be sent to http://keycloak.k3s.fitmate/... which no browser can resolve.
  #
  # The previous non-prod special case encoded "dev and stg are internal-only". That stopped being true
  # when IN-15 gave them public hostnames, and the stale value silently rejected every browser-minted
  # token — a 401 on a token that was correctly signed, unexpired and correctly audienced.
  #
  # ⚠️ Tokens minted through the in-cluster host are now REJECTED BY DESIGN. That host stays valid for
  # JWKS and for Terraform's admin access; it must not be used to obtain a user token. Verify with
  # `devops-tools/scripts/keycloak/e2e-verify.sh --mint-host public` — a `cluster` mint must now FAIL.
  #
  # JWKS is unaffected below: it is FETCHED, never COMPARED, so it stays on the in-cluster Service URL
  # (pods cannot resolve the public host). Do not "make these consistent".
  issuer_host = local.environment == "prod" ? "https://auth.fitmate.me" : "https://auth-${local.environment}.fitmate.me"

  secrets = {
    # ── Per-app GHCR image-pull creds (value = the GitHub read:packages PAT). Per-env folder so each
    #    app's fitmate-<svc>-<env>-eso role can read its own copy. Add a line per image-pulling app.
    "trainee/ghcr-pull" = { username = local.backend_github_username, token = local.backend_github_token }
    "website/ghcr-pull" = { username = local.backend_github_username, token = local.backend_github_token }
    "trainer/ghcr-pull" = { username = local.backend_github_username, token = local.backend_github_token }
    # DRIFT REPAIR (2026-08-20): booking/inquiry/admin/payment were pulling private GHCR images in dev
    # from Vault docs that existed ONLY in Vault — never declared here. Their ExternalSecrets read
    # dev/<svc>/ghcr-pull and reported SecretSynced, so nothing looked wrong, but a Vault rebuild would
    # not have restored them and `terragrunt apply` would not have recreated them. Same PAT as above;
    # writing these is idempotent (no _RANDOM_), so applying re-declares what is already there.
    "booking/ghcr-pull" = { username = local.backend_github_username, token = local.backend_github_token }
    "inquiry/ghcr-pull" = { username = local.backend_github_username, token = local.backend_github_token }
    "admin/ghcr-pull"   = { username = local.backend_github_username, token = local.backend_github_token }
    "payment/ghcr-pull" = { username = local.backend_github_username, token = local.backend_github_token }

    # ── Image-pull creds for services that have an ESO ROLE but had no ghcr-pull path (IN-11).
    #    Every service in vault-auths' `eso_service_sa` map gets a role provisioned ahead of its
    #    deployment; the matching Vault doc was only ever added for services already deployed. The
    #    result is invisible until deploy day, when the pod reports ImagePullBackOff — which reads as
    #    a registry/credential fault and is actually a missing Vault path. Restores role↔secret parity.
    "admin-website/ghcr-pull" = { username = local.backend_github_username, token = local.backend_github_token }
    "gateway/ghcr-pull"       = { username = local.backend_github_username, token = local.backend_github_token }
    "media/ghcr-pull"         = { username = local.backend_github_username, token = local.backend_github_token }
    "notification/ghcr-pull"  = { username = local.backend_github_username, token = local.backend_github_token }


    # ── Auth.js session-encryption key for the website BFF (IN-11).
    #    Its OWN path, NOT website/creds: that path is written whole-map by the keycloak stack's
    #    `vault_kv_secret_v2.client_secret["fitmate-website"]`, which sets `disable_read = true`.
    #    Two stacks writing one path would silently clobber each other's keys on every apply — the
    #    same trap already called out for admin/params and the e2e path in dev/keycloak/fitmate.
    #    The website's ESO role reads `fitmate/data/<env>/website/*`, so a sibling path needs no
    #    policy change.
    #
    #    Managed rather than hand-generated because once the website has >1 replica it MUST be
    #    identical across pods (else a session minted by pod A is undecryptable by pod B → random
    #    intermittent logouts) and stable across restarts (else every deploy signs everyone out).
    #    44 chars over random_password's charset ≈ 260 bits — Auth.js takes any high-entropy string.
    "website/session" = { AUTH_SECRET = "{ _RANDOM_ = 44 }" }


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
      # DB DSNs — composed by vault-secrets: the `{{...:password}}` token is replaced with the
      # generated password of the sibling creds secret (kept in trainee/* so the app's own ESO role
      # can read it). host/db/user match the dev database/trainee unit (db trainee_<env>, owner
      # trainee_app_<env>). PG is the external LAN host (192.168.105.10) — pods must route to it.
      DATABASE_WRITE_DB_CONNECTION_STRING = "postgresql://trainee_app_${local.environment}:{{database/trainee/app/creds:password}}@192.168.105.10:5432/trainee_${local.environment}?sslmode=disable"
      DATABASE_READ_DB_CONNECTION_STRING  = "postgresql://trainee_ro_${local.environment}:{{database/trainee/ro/creds:password}}@192.168.105.10:5432/trainee_${local.environment}?sslmode=disable"
    }

    # ── trainer-service (IN-6): mirrors trainee/params. Keycloak token-validation config + DB DSNs.
    #    DB creds (database/trainer/app|ro/creds) already seeded above; the {{...:password}} token embeds
    #    the generated pw. DB trainer_<env> owned by trainer_app_<env> is provisioned by the dev/database
    #    unit (IN-7). PG on the external LAN host (192.168.105.10).
    "trainer/params" = {
      KEYCLOAK_ISSUER                     = "${local.issuer_host}/realms/${local.realm_name}"
      KEYCLOAK_AUDIENCE                   = "fitmate-backend"
      KEYCLOAK_JWKSURL                    = "http://keycloak-service.keycloak.svc.cluster.local:8080/realms/${local.realm_name}/protocol/openid-connect/certs"
      DATABASE_WRITE_DB_CONNECTION_STRING = "postgresql://trainer_app_${local.environment}:{{database/trainer/app/creds:password}}@192.168.105.10:5432/trainer_${local.environment}?sslmode=disable"
      DATABASE_READ_DB_CONNECTION_STRING  = "postgresql://trainer_ro_${local.environment}:{{database/trainer/ro/creds:password}}@192.168.105.10:5432/trainer_${local.environment}?sslmode=disable"
    }

    # ── DRIFT REPAIR (2026-08-20) — booking / inquiry / admin / payment.
    #
    # The "MVP: only trainee migrated; fan out per service in Phase 2" note above was never actioned,
    # yet all four services have been running in dev for weeks. Their ExternalSecrets read
    # dev/<svc>/params and report SecretSynced=True, because the docs DO exist in Vault — they were
    # created out-of-band and never written back into this file.
    #
    # Net effect: dev worked but was NOT REPRODUCIBLE. Wipe Vault (the documented lab-rebuild path)
    # and four of six services never come back, with `terragrunt apply` unable to restore them.
    # Nothing goes red in that scenario until a pod tries to start.
    #
    # Key sets below were read from the LIVE materialised Secrets, not copied from trainee — payment
    # deliberately differs (write-only, no RO role, no Kafka/Redis).
    # Safe to apply: every value here is deterministic (static strings + {{...:password}} composition
    # tokens referencing creds already declared above). NO _RANDOM_, so no password re-roll cascade.

    "booking/params" = {
      KEYCLOAK_ISSUER                     = "${local.issuer_host}/realms/${local.realm_name}"
      KEYCLOAK_AUDIENCE                   = "fitmate-backend"
      KEYCLOAK_JWKSURL                    = "http://keycloak-service.keycloak.svc.cluster.local:8080/realms/${local.realm_name}/protocol/openid-connect/certs"
      DATABASE_WRITE_DB_CONNECTION_STRING = "postgresql://booking_app_${local.environment}:{{database/booking/app/creds:password}}@192.168.105.10:5432/booking_${local.environment}?sslmode=disable"
      DATABASE_READ_DB_CONNECTION_STRING  = "postgresql://booking_ro_${local.environment}:{{database/booking/ro/creds:password}}@192.168.105.10:5432/booking_${local.environment}?sslmode=disable"
    }

    "inquiry/params" = {
      KEYCLOAK_ISSUER                     = "${local.issuer_host}/realms/${local.realm_name}"
      KEYCLOAK_AUDIENCE                   = "fitmate-backend"
      KEYCLOAK_JWKSURL                    = "http://keycloak-service.keycloak.svc.cluster.local:8080/realms/${local.realm_name}/protocol/openid-connect/certs"
      DATABASE_WRITE_DB_CONNECTION_STRING = "postgresql://inquiry_app_${local.environment}:{{database/inquiry/app/creds:password}}@192.168.105.10:5432/inquiry_${local.environment}?sslmode=disable"
      DATABASE_READ_DB_CONNECTION_STRING  = "postgresql://inquiry_ro_${local.environment}:{{database/inquiry/ro/creds:password}}@192.168.105.10:5432/inquiry_${local.environment}?sslmode=disable"
    }

    # admin also carries KEYCLOAK_CLIENTSECRET, delivered from the SEPARATE doc dev/admin/keycloak/creds
    # via a per-key `data` ref (not this extract). That doc is deliberately NOT declared here — it holds
    # a real Keycloak client secret owned by the keycloak/fitmate unit, and seeding it from this file
    # would overwrite a live credential. Tracked separately; see IN backlog.
    "admin/params" = {
      KEYCLOAK_ISSUER                     = "${local.issuer_host}/realms/${local.realm_name}"
      KEYCLOAK_AUDIENCE                   = "fitmate-backend"
      KEYCLOAK_JWKSURL                    = "http://keycloak-service.keycloak.svc.cluster.local:8080/realms/${local.realm_name}/protocol/openid-connect/certs"
      DATABASE_WRITE_DB_CONNECTION_STRING = "postgresql://admin_app_${local.environment}:{{database/admin/app/creds:password}}@192.168.105.10:5432/admin_${local.environment}?sslmode=disable"
      DATABASE_READ_DB_CONNECTION_STRING  = "postgresql://admin_ro_${local.environment}:{{database/admin/ro/creds:password}}@192.168.105.10:5432/admin_${local.environment}?sslmode=disable"
    }

    # payment is WRITE-ONLY (matches the `database/payment/app/creds` note above — no RO role exists).
    # Its live Secret has exactly 4 keys: no DATABASE_READ, no Kafka, no Redis. Do NOT "normalise" this
    # to match the others — payment runs Kafka in mock mode in dev and uses no cache.
    "payment/params" = {
      KEYCLOAK_ISSUER                     = "${local.issuer_host}/realms/${local.realm_name}"
      KEYCLOAK_AUDIENCE                   = "fitmate-backend"
      KEYCLOAK_JWKSURL                    = "http://keycloak-service.keycloak.svc.cluster.local:8080/realms/${local.realm_name}/protocol/openid-connect/certs"
      DATABASE_WRITE_DB_CONNECTION_STRING = "postgresql://payment_app_${local.environment}:{{database/payment/app/creds:password}}@192.168.105.10:5432/payment_${local.environment}?sslmode=disable"
    }
  }

  tags = {
    created_by   = "terraform"
    environment  = local.environment
    organization = local.org_infras_org
  }
}
