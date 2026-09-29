locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  keycloak_url = get_env("KEYCLOAK_URL", "http://keycloak.k3s.fitmate")

  # ── e2e test harness client (IN-17) — NON-PROD ONLY ─────────────────────────────────────────
  # The ONLY client in the realm with the password grant enabled, and it exists for exactly one
  # reason: to make "does a real token get accepted by a real service?" a script instead of a
  # browser ritual. That assertion is the one that matters most and was, until now, the only one
  # that could not be automated — which is precisely how IN-16 survived undetected.
  #
  # ⚠️ It is appended by a `local.environment == "prod" ? [] : [...]` guard below, NOT written
  # inline. A confidential client with direct grants bypasses PKCE, MFA and brokered social login
  # and is a standing credential-stuffing target. Gating it structurally means prod cannot acquire
  # it by someone forgetting — the config makes it impossible, rather than the reviewer catching it.
  #
  # standard_flow stays OFF: this client must never appear in a browser. service_accounts stays
  # OFF: it acts as a USER (trainee1), not as itself — a machine identity would test the wrong
  # thing entirely.
  e2e_clients = local.environment == "prod" ? [] : [
    {
      client_id                    = "fitmate-e2e-test"
      name                         = "FITMate e2e test harness (NON-PROD ONLY)"
      access_type                  = "CONFIDENTIAL" # secret pushed to Vault below, never to .envrc
      standard_flow_enabled        = false          # never used in a browser
      direct_access_grants_enabled = true           # THE reason this client exists
      service_accounts_enabled     = false          # acts as a user, not as itself
      # Same aud as every other client — Keycloak's default is `account`, which every FitMate
      # service rejects. Without this the harness would fail on audience and mask an issuer bug.
      audiences = ["fitmate-backend"]
      # ── Caller-identity claim (B-M01) ────────────────────────────────────────────────────────
      # Copies the `trainer_id` USER ATTRIBUTE into this client's access token.
      #
      # WHY: media-service stores identity documents under a `trainer_id` taken from a multipart
      # FORM FIELD and never compares it to identity.sub, so any authenticated user can write
      # into another trainer's document directory. The same mismatch locks legitimate owners OUT
      # of their own documents, because the read route compares identity.sub against a path
      # segment that actually holds the trainers ROW id (d98077d6-… vs sub 6d7c8b39-…) — a
      # comparison that can never be true, leaving only the admin branch working.
      #
      # A signed claim removes the forgeable input entirely.
      #
      # ⚠️ The claim is only as trustworthy as the attribute behind it. `trainer_id` MUST be
      # written by trainer-service using its own admin credentials (fitmate-trainer-backend,
      # manage-users) and NEVER by the end user — otherwise this relocates the forgery rather
      # than removing it.
      #
      # ⚠️ Until every existing trainer is back-filled, tokens for older accounts carry NO
      # claim. media-service must treat an absent claim as a REFUSAL, never as a reason to fall
      # back to the form field — a fallback silently restores the vulnerability this closes.
      user_attribute_claims = [
        {
          user_attribute = "trainer_id"
          claim_name     = "trainer_id"
        },
      ]
    },
  ]
}

terraform {
  source = "../../../../../../devops-terraform-modules//on-prem/shared/keycloak"
}

# Run ONLY when both external deps are reachable: Keycloak (the provider target) AND Vault (the
# user-password dependency + the client-secret push). Same pattern as the database units' Vault gate.
exclude {
  if = run_cmd("--terragrunt-quiet", "bash", "-c",
    "curl -fs -o /dev/null --max-time 3 $${KEYCLOAK_URL:-http://keycloak.k3s.fitmate}/realms/master/.well-known/openid-configuration && curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.fitmate}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

dependency "vault-secrets" {
  config_path = "../../vault-secrets"
  mock_outputs = {
    secrets = {
      "keycloak/fitmate/trainee1/creds" = { username = "trainee1", password = "MOCK" }
    }
  }
  # plan/validate may use mocks (fills a newly-added sub-key); apply requires real applied outputs.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "deep_map_only"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Vault provider now comes FROM keycloak.hcl (combined realm partial). Do NOT include vault.hcl here, or
# you get duplicate required_providers + a provider-vault.tf generate-path clash.
include "keycloak" {
  path = find_in_parent_folders("keycloak.hcl")
}

inputs = {
  keycloak_url = local.keycloak_url

  # Browser-facing host for the broker-callback OUTPUT (IN-14). keycloak_url above is the
  # in-cluster ADMIN address the Terraform provider talks to; a provider redirects a BROWSER,
  # and Google/Facebook both require https — so rendering callbacks from keycloak_url handed
  # out a redirect_uri that could never match. Output-only; changes no resource.
  public_base_url = "https://auth-stg.fitmate.me"

  realm = {
    # One shared Keycloak instance, one realm PER ENV: fitmate-dev / fitmate-stg, and plain `fitmate`
    # for prod. Token issuer = http://keycloak.k3s.fitmate/realms/<this name> (per-env <svc>/params).
    name         = local.environment == "prod" ? "fitmate" : "fitmate-${local.environment}"
    enabled      = true
    display_name = "FITMate"
    ssl_required = "none" # HTTP lab: Keycloak reached at http://keycloak.k3s.fitmate via Traefik

    # Services gate on realm_access.roles.
    # NOTE: role is "administrator", NOT "admin" — Keycloak 26.4.0+ has an FGAP regression that blocks
    # updating a realm role literally named "admin" (403), even for a super-admin. The FitMate services
    # must gate on `administrator` in realm_access.roles. (keycloak/keycloak#43579, #44371)
    roles = ["trainee", "trainer", "administrator", "super_admin"]

    # ── Custom user-profile attributes (B-M01) ────────────────────────────────────────────────
    # `trainer_id` must be DECLARED or Keycloak 26 silently discards it: the admin PUT returns
    # 204 and the value never lands, so the protocol mapper has nothing to copy and no token
    # ever carries the claim. Measured against live dev 2026-09-29.
    #
    # edit is ADMIN-ONLY (the module default). The whole point of B-M01 is that media-service
    # stops trusting a client-supplied trainer id; letting the user edit the attribute would
    # move the forgery into Keycloak rather than remove it. Only trainer-service writes it,
    # using fitmate-trainer-backend's manage-users grant.
    user_profile_attributes = [
      {
        name         = "trainer_id"
        display_name = "Trainer ID"
      },
    ]

    clients = concat([
      {
        client_id                    = "fitmate-website"
        name                         = "FITMate Website (BFF)"
        access_type                  = "CONFIDENTIAL" # issues a client_secret (Auth.js BFF holds it)
        standard_flow_enabled        = true           # Authorization Code
        direct_access_grants_enabled = false
        pkce_code_challenge_method   = "S256"
        # ── web-stg origin (IN-36, 2026-09-25) ──────────────────────────────────────────────
        # Until now this client allowed ONLY localhost:3000, because there was no staging
        # website to point at. There is one as of today (gitops PR #401, chart 1.0.0, verified
        # serving HTTP 200 in-cluster), so every sign-in from https://web-stg.fitmate.me would
        # fail with Keycloak's HTTP 400 "Invalid parameter: redirect_uri".
        #
        # That failure is 100% of sign-ins on the first deployed rollout, and it renders on
        # KEYCLOAK's own error page while the website pod sits 1/1 Running with clean logs —
        # so it reads as a website bug and is not one. dev hit exactly this on 2026-08-24.
        #
        # localhost:3000 is KEPT, not replaced: it is how the app is run against stg Keycloak
        # locally, and dropping it would trade one broken environment for another.
        #
        # No .k3s.fitmate lab origin here, unlike dev: that alias exists to bypass the
        # Cloudflare Access interstitial, and stg's Access `apps` map is empty (applied
        # 2026-09-25), so web-stg is reachable without one.
        valid_redirect_uris = [
          "http://localhost:3000/api/auth/callback/keycloak",
          "https://web-stg.fitmate.me/api/auth/callback/keycloak",
        ]
        # Post-logout is a SEPARATE allowlist in Keycloak 26 — a host valid for LOGIN is NOT
        # thereby valid for LOGOUT. Omitting this leaves sign-in working and sign-out failing
        # with "Invalid parameter: post_logout_redirect_uri", which is the harder half to
        # attribute because the user is already authenticated when it breaks.
        valid_post_logout_redirect_uris = [
          "http://localhost:3000",
          "https://web-stg.fitmate.me",
        ]
        # web_origins is CORS. The BFF flow does not strictly need it — Auth.js performs the
        # code exchange server-side (Node -> Keycloak) and logout is a browser NAVIGATION, not
        # an XHR. Kept at parity with the two lists above so they do not diverge for an
        # unstated reason.
        web_origins = [
          "http://localhost:3000",
          "https://web-stg.fitmate.me",
        ]
        # CRITICAL: backend services require aud contains fitmate-backend (Keycloak default aud = account).
        audiences = ["fitmate-backend"]
        # ── Caller-identity claim (B-M01) ────────────────────────────────────────────────────────
        # Copies the `trainer_id` USER ATTRIBUTE into this client's access token.
        #
        # WHY: media-service stores identity documents under a `trainer_id` taken from a multipart
        # FORM FIELD and never compares it to identity.sub, so any authenticated user can write
        # into another trainer's document directory. The same mismatch locks legitimate owners OUT
        # of their own documents, because the read route compares identity.sub against a path
        # segment that actually holds the trainers ROW id (d98077d6-… vs sub 6d7c8b39-…) — a
        # comparison that can never be true, leaving only the admin branch working.
        #
        # A signed claim removes the forgeable input entirely.
        #
        # ⚠️ The claim is only as trustworthy as the attribute behind it. `trainer_id` MUST be
        # written by trainer-service using its own admin credentials (fitmate-trainer-backend,
        # manage-users) and NEVER by the end user — otherwise this relocates the forgery rather
        # than removing it.
        #
        # ⚠️ Until every existing trainer is back-filled, tokens for older accounts carry NO
        # claim. media-service must treat an absent claim as a REFUSAL, never as a reason to fall
        # back to the form field — a fallback silently restores the vulnerability this closes.
        user_attribute_claims = [
          {
            user_attribute = "trainer_id"
            claim_name     = "trainer_id"
          },
        ]
      },
      {
        # ── admin-service backend (B-047 / Keycloak cutover) ──────────────────────────────────
        # A MACHINE identity, not a browser client: admin-service calls the Keycloak ADMIN REST API
        # as itself (client_credentials) to create admins and assign realm roles. No user ever logs
        # in through it, hence standard_flow/direct_grants OFF.
        client_id                    = "fitmate-admin-backend"
        name                         = "FITMate Admin Service (backend)"
        access_type                  = "CONFIDENTIAL" # issues the client_secret pushed to Vault below
        standard_flow_enabled        = false          # never used in a browser
        direct_access_grants_enabled = false          # no password grant
        service_accounts_enabled     = true           # THE machine identity
        # Least privilege: create/read users + assign realm roles. Deliberately NOT "realm-admin",
        # which is full control of the realm — a leaked secret would then own the whole IdP.
        service_account_roles = ["manage-users", "view-users"]
        # Its own tokens must carry aud=fitmate-backend like every other client (KC default is `account`).
        audiences = ["fitmate-backend"]
      },
      {
        # ── trainer-service backend (IN-34) ───────────────────────────────────────────────────
        # A MACHINE identity, not a browser client. At trainer-profile-creation time
        # trainer-service calls the Keycloak ADMIN REST API as itself (client_credentials) to map
        # the `trainer` realm role onto the user who just self-registered. No user logs in through
        # it, hence standard_flow/direct_grants OFF; service_accounts ON is THE machine identity.
        #
        # This mirrors fitmate-trainee-backend above (spec 074 / SCRUM-348) exactly, and is
        # deliberately a SEPARATE client rather than a reuse of it — same two reasons:
        #   1. BLAST RADIUS / AUDIT. A leaked trainer secret buys only "assign trainer role", and
        #      "which service assigned this role" stays answerable.
        #   2. LIFECYCLE. trainer-service and trainee-service rotate/rollback independently.
        #
        # WHY THIS EXISTS: without it a self-registered trainer receives no `trainer` realm role,
        # so the website's userTypeFromRoles() (identity.ts:211) resolves them to `trainee` and
        # renders "Học viên" plus trainee routing for a real trainer. MEASURED 2026-09-23: a user
        # whose GET /trainers/me returned a real id carried roles
        # ["default-roles-fitmate-dev","offline_access","uma_authorization"] — no `trainer`.
        client_id                    = "fitmate-trainer-backend"
        name                         = "FITMate Trainer Service (backend)"
        access_type                  = "CONFIDENTIAL" # issues the client_secret pushed to Vault below
        standard_flow_enabled        = false          # never used in a browser
        direct_access_grants_enabled = false          # no password grant
        service_accounts_enabled     = true           # THE machine identity
        # ── Least privilege: identical grant to trainee-backend ───────────────────────────────
        # 🔴 `view-realm` IS REQUIRED TO ASSIGN A REALM ROLE — do not "tidy" it away as unused.
        # Keycloak's role-mapping API takes the role's **id**, not its name, so assigning `trainer`
        # begins with GET /admin/realms/{realm}/roles/trainer to resolve the id. That GET is gated
        # by `view-realm`; manage-users alone authorises the role-mapping POST that FOLLOWS but NOT
        # the lookup before it. MEASURED 2026-09-01 on this realm (admin-backend trap #3): a token
        # with [manage-users view-users] got 403 on GET /roles/{name}; view-realm moved it to 200.
        #
        # `view-users` is intentionally OMITTED. trainer-service operates on the user it already
        # knows — the authenticated caller's `sub` from the request JWT — so it never lists or
        # searches the user directory. The Go side MUST operate by `sub` and MUST NOT call
        # GET /users?search=… , which needs view-users/query-users and would 403.
        service_account_roles = ["manage-users", "view-realm"]
        # Its own tokens must carry aud=fitmate-backend like every other client (KC default is `account`).
        audiences = ["fitmate-backend"]
      },
    ], local.e2e_clients)

    # e2e test user. firstName/lastName/email/email_verified are REQUIRED for a password-grant
    # fixture — Keycloak 26's declarative user profile otherwise triggers VERIFY_PROFILE at login and
    # the direct grant fails with "Account is not fully set up" (with an empty requiredActions list).
    users = [
      {
        username       = "trainee1"
        email          = "trainee1@fitmate.local"
        first_name     = "Trainee"
        last_name      = "One"
        email_verified = true
        realm_roles    = ["trainee"]
      },
    ]

    # ── Social login (IN-14) ────────────────────────────────────────────────────────────────────
    # Google as a realm IDENTITY PROVIDER. Keycloak brokers the OAuth exchange and issues a NORMAL
    # Keycloak JWT, so no service changes: browser -> Keycloak -> Google -> Keycloak -> JWT.
    #
    # ⚠️ TOKENS MINTED HERE CARRY iss = https://auth-stg.fitmate.me/realms/fitmate-stg, because
    # hostname.strict=false makes Keycloak derive the issuer from X-Forwarded-Host. stg/env.hcl
    # still sets KEYCLOAK_ISSUER to the in-cluster host, so services will REJECT such a token with
    # an exact-string issuer mismatch (go-oidc NewVerifier compares byte-for-byte). See IN-16 —
    # social login is not usable end-to-end in stg until that is resolved, even though the login
    # itself will succeed and Keycloak will report everything healthy.
    #
    # ⚠️ trust_email = false is a SECURITY choice, not a default to inherit — ADR 2026-08-21.
    identity_providers = [
      {
        alias = "google"
        # DEDICATED client `FITMate Keycloak — stg` (created 2026-08-23). Its OWN client, not shared
        # with dev or the Firebase auto-created client: a leaked stg secret must not log anyone into
        # another env. See 30-references/runbook-google-facebook-oauth-clients-per-env.
        client_id = "290257968475-hce0udono8a73edh1d2e2nld822rne24.apps.googleusercontent.com"
        # ⚠️ _STG suffix, NOT a bare GOOGLE_CLIENTSECRET. One shared variable can only hold one env's
        # secret, and applying stg while it holds dev's value gives a SUCCESSFUL apply and a login
        # that fails at the provider. An unset variable yields "" and the module SKIPS the provider
        # (see the `identity_providers_skipped` output) rather than creating one with a blank secret.
        client_secret  = get_env("GOOGLE_CLIENTSECRET_STG", "")
        default_scopes = "openid profile email"
        trust_email    = false
        sync_mode      = "IMPORT"
      },
      # Facebook: DEFERRED to a post-launch phase (2026-08-23, owner's call). To add, create a
      # `FitMate stg` TEST APP under the `FitMate Prod` parent and register
      #   https://auth-stg.fitmate.me/realms/fitmate-stg/broker/facebook/endpoint
      # on the test app itself — parent settings do NOT propagate after creation.
    ]
  }

  # trainee1 password from Vault (generated by vault-secrets).
  user_passwords = {
    trainee1 = dependency.vault-secrets.outputs.secrets["keycloak/fitmate/trainee1/creds"]["password"]
  }

  # Hand the GENERATED fitmate-website secret straight to Vault → ESO → website (no manual copy).
  # mount must match the vault-auths KV mount (the org). path mirrors the local/<svc>/creds layout.
  vault_push = {
    enabled = true
    mount   = "fitmate" # the shared org KV mount
    clients = merge({
      # env-scoped folder inside the mount → fitmate/data/<env>/website/creds
      "fitmate-website" = { path = "${local.environment}/website/creds", key = "AUTH_KEYCLOAK_SECRET" }
      # admin-service's Admin-API client secret → ESO → the fitmate-admin-<env> namespace.
      # Its OWN path (not admin/params): vault_kv_secret_v2 manages a path's whole data map, so
      # writing into admin/params would clobber every other param key.
      "fitmate-admin-backend" = { path = "${local.environment}/admin/keycloak/creds", key = "KEYCLOAK_CLIENTSECRET" }
      # trainer-service's Admin-API client secret (IN-34) → ESO → the fitmate-trainer-<env>
      # namespace. Its OWN path (not trainer/params): vault_kv_secret_v2 manages a path's WHOLE
      # data map, so writing into trainer/params would clobber KEYCLOAK_ISSUER / KEYCLOAK_JWKSURL
      # / the DB DSNs already there on every apply.
      # ESO needs NO policy change: fitmate-trainer-<env>-eso already reads
      # fitmate/data/<env>/trainer/* and a Vault trailing `*` spans `/` (verified 2026-09-23:
      # `trainer` is already an eso_service_sa entry in <env>/vault-auths/terragrunt.hcl).
      "fitmate-trainer-backend" = { path = "${local.environment}/trainer/keycloak/creds", key = "KEYCLOAK_CLIENTSECRET" }
      }, local.environment == "prod" ? {} : {
      # e2e harness secret (IN-17). Its OWN path — vault_kv_secret_v2 manages a path's whole data
      # map, so writing into an existing params path would clobber every other key there.
      # Vault, not .envrc.local: the harness runs in CI, and a hand-copied secret is one that
      # eventually gets pasted somewhere it shouldn't be.
      "fitmate-e2e-test" = { path = "${local.environment}/e2e/keycloak/creds", key = "KEYCLOAK_CLIENTSECRET" }
    })
  }
}
