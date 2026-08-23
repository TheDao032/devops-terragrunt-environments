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

    clients = concat([
      {
        client_id                       = "fitmate-website"
        name                            = "FITMate Website (BFF)"
        access_type                     = "CONFIDENTIAL" # issues a client_secret (Auth.js BFF holds it)
        standard_flow_enabled           = true           # Authorization Code
        direct_access_grants_enabled    = false
        pkce_code_challenge_method      = "S256"
        valid_redirect_uris             = ["http://localhost:3000/api/auth/callback/keycloak"]
        valid_post_logout_redirect_uris = ["http://localhost:3000"]
        web_origins                     = ["http://localhost:3000"]
        # CRITICAL: backend services require aud contains fitmate-backend (Keycloak default aud = account).
        audiences = ["fitmate-backend"]
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
      }, local.environment == "prod" ? {} : {
      # e2e harness secret (IN-17). Its OWN path — vault_kv_secret_v2 manages a path's whole data
      # map, so writing into an existing params path would clobber every other key there.
      # Vault, not .envrc.local: the harness runs in CI, and a hand-copied secret is one that
      # eventually gets pasted somewhere it shouldn't be.
      "fitmate-e2e-test" = { path = "${local.environment}/e2e/keycloak/creds", key = "KEYCLOAK_CLIENTSECRET" }
    })
  }
}
