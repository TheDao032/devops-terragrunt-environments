locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  keycloak_url = get_env("KEYCLOAK_URL", "http://keycloak.k3s.fitmate")
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

    clients = [
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
    ]

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
    # Google/Facebook as realm IDENTITY PROVIDERS. Keycloak brokers the OAuth exchange and issues a
    # NORMAL Keycloak JWT, so no service changes: browser -> Keycloak -> Google -> Keycloak -> JWT.
    #
    # REPLACES the approach in closed PR #14, which delivered the provider secret to trainer-service
    # as SUPERTOKENS_THIRDPARTY_GOOGLE_CLIENTSECRET. The application never sees these.
    #
    # client_id is NOT secret and is committed here deliberately — it makes the config
    # self-documenting, and it is visible in the browser during the OAuth redirect anyway.
    # client_secret comes from .envrc.local; an unset variable yields "" and the module SKIPS that
    # provider rather than creating one with a blank secret (which would render a login button that
    # fails at the code exchange). `terragrunt output identity_providers_skipped` lists any skipped.
    #
    # ⚠️ BEFORE THIS WORKS: the broker callback must be registered at each provider's console —
    #   http://keycloak.k3s.fitmate/realms/fitmate-dev/broker/google/endpoint
    #   http://keycloak.k3s.fitmate/realms/fitmate-dev/broker/facebook/endpoint
    # Terraform cannot do that. `terragrunt output identity_provider_redirect_uris` prints them.
    #
    # ⚠️ trust_email = false is a SECURITY choice, not a default to inherit. With true, a social
    # login whose email matches an existing account is trusted without verification — so anyone able
    # to create a provider account bearing a victim's address inherits that FITMate account.
    # Changing it needs a written decision.
    identity_providers = [
      # ⚠️ PER-ENV SECRET VARIABLES (…_DEV / …_STG / …_PROD), not a bare GOOGLE_CLIENTSECRET.
      # Each env has its OWN OAuth client, so one shared variable can only ever hold one env's
      # secret — and applying stg while it holds dev's value produces a SUCCESSFUL apply and a
      # login that fails at the provider. Suffixing makes that impossible rather than merely
      # unlikely. Export in .envrc.local:
      #     export GOOGLE_CLIENTSECRET_DEV="GOCSPX-…"
      #     export FACEBOOK_CLIENTSECRET_DEV="…"
      # An unset variable yields "" and the module SKIPS that provider (visible in the
      # `identity_providers_skipped` output) rather than creating one with a blank secret.
      {
        alias = "google"
        # DEDICATED client `FITMate Keycloak — dev` (created 2026-08-22). Previously this reused
        # the Firebase auto-created client (290257968475-d77r4sl3…), which also backs the mobile
        # app's google_sign_in serverClientId and Firebase Crashlytics/FCM. Sharing it meant one
        # credential served three unrelated consumers — rotating for one silently risked the
        # others, which is exactly the coupling SCRUM-235 existed to remove.
        # DO NOT point this back at the Firebase client, and do not delete that client: the mobile
        # app hardcodes its ID in Dart (auth_repository.dart), so removing it breaks mobile
        # Google sign-in immediately (see SCRUM-244).
        client_id      = "290257968475-mp8akbb8dgjkhmgau7bpdcptk74bh84e.apps.googleusercontent.com"
        client_secret  = get_env("GOOGLE_CLIENTSECRET_DEV", "")
        default_scopes = "openid profile email"
        trust_email    = false
        sync_mode      = "IMPORT"
      },
      # ── Facebook: DEFERRED to a post-launch phase (2026-08-23, owner's call) ────────────────────
      # Removed rather than left disabled, because the Meta app it referenced (1507947667436834) has
      # been DELETED — that ID is now dangling. Keeping an `enabled = false` entry would preserve a
      # reference to a nonexistent app and mislead the next reader.
      #
      # The replacement parent app is `FitMate Prod`. To re-enable, per
      # 30-references/runbook-google-facebook-oauth-clients-per-env:
      #   1. From `FitMate Prod`: app dropdown -> Create Test App -> "FitMate dev"
      #      (test apps get their OWN App ID + secret, are always in Development mode — so only
      #       users with a role can log in — and need NO App Review, unlike a standalone Live app)
      #   2. In that test app: Facebook Login -> Settings -> Valid OAuth Redirect URIs:
      #        https://auth-dev.fitmate.me/realms/fitmate-dev/broker/facebook/endpoint
      #      Parent settings do NOT propagate after creation — set it on the test app itself.
      #   3. export FACEBOOK_CLIENTSECRET_DEV in .envrc.local
      #   4. restore the block below and apply
      #
      # {
      #   alias         = "facebook"
      #   client_id     = "<FitMate dev test-app App ID>"
      #   client_secret = get_env("FACEBOOK_CLIENTSECRET_DEV", "")
      #   trust_email   = false   # ADR 2026-08-21 — do not change without superseding it
      #   sync_mode     = "IMPORT"
      # },
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
    clients = {
      # env-scoped folder inside the mount → fitmate/data/<env>/website/creds
      "fitmate-website" = { path = "${local.environment}/website/creds", key = "AUTH_KEYCLOAK_SECRET" }
      # admin-service's Admin-API client secret → ESO → the fitmate-admin-<env> namespace.
      # Its OWN path (not admin/params): vault_kv_secret_v2 manages a path's whole data map, so
      # writing into admin/params would clobber every other param key.
      "fitmate-admin-backend" = { path = "${local.environment}/admin/keycloak/creds", key = "KEYCLOAK_CLIENTSECRET" }
    }
  }
}
