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
  public_base_url = "https://auth-dev.fitmate.me"

  realm = {
    # One shared Keycloak instance, one realm PER ENV: fitmate-dev / fitmate-stg, and plain `fitmate`
    # for prod. Token issuer = http://keycloak.k3s.fitmate/realms/<this name> (per-env <svc>/params).
    name         = local.environment == "prod" ? "fitmate" : "fitmate-${local.environment}"
    enabled      = true
    display_name = "FITMate"
    ssl_required = "none" # HTTP lab: Keycloak reached at http://keycloak.k3s.fitmate via Traefik

    # ── Login & registration policy (ADR-049 D3 + D4, owner decision 2026-08-24) ─────────────────
    # The login page is rendered from realm state, so these decide what it OFFERS. Both were off,
    # which is what the login theme work is blocked on.
    #
    # D3 — accept the email address as the identifier. With this off Keycloak renders the literal
    # label "Username" and REJECTS every user who types their email, while the V3 auth design's own
    # screen is captioned "Đăng nhập bằng email và mật khẩu". The design promised email and the
    # realm refused it; they cannot both ship.
    #
    # ⚠️ On its own this permits email as an ALTERNATIVE identifier — Keycloak renders "Username or
    # email" and accepts either. It does NOT by itself make the email the identity; that is
    # `registration_email_as_username`, set below.
    login_with_email_allowed = true

    # D4 — self-service sign-up. Keycloak owns the CREDENTIAL step; the website completes the
    # profile after first sign-in. That split is forced, not tidy: trainer sign-up needs ID-card
    # images and certificate uploads, which Keycloak's registration page cannot collect.
    registration_allowed = true

    # ── D4b — the email IS the identity (owner decision 2026-08-24) ──────────────────────────────
    # Removes the separate username field from the registration form and stores the email as the
    # username. Not a preference: the V3 auth design was MEASURED to contain zero username fields,
    # on any screen. Without this, Keycloak's sign-up page renders a username input the design has
    # no slot for, and the two cannot both ship.
    #
    # Paired with edit_username_allowed left at its default `false` — the shared module REFUSES the
    # combination (validation in variables.tf), because a user who can edit their username can edit
    # away the very invariant this flag establishes.
    #
    # 🔴 THIS BREAKS PASSWORD GRANT BY BARE USERNAME. Isolated on a throwaway realm, both rows with
    # login_with_email_allowed = true: with this ON, `username=trainee1` is rejected with
    # `invalid_grant / Invalid user credentials` while `username=trainee1@fitmate.local` succeeds.
    # The seeded users' bare names stop being valid identifiers the moment this applies.
    #
    # ⚠️ ORDERING — this unit must be APPLIED only once devops-tools is on a revision containing
    # scripts/keycloak/e2e-verify.sh's E2E_LOGIN_IDENTIFIER default (merged there as PR #19, base
    # `dev`). That harness is IN-17. Applying this first turns IN-17 red with a message that looks
    # like a credential problem rather than an identifier-shape change. Escape hatch if it does:
    # E2E_LOGIN_IDENTIFIER=trainee1@fitmate.local (the new default), or pin the old behaviour with
    # the bare name only while this flag is off.
    #
    # WHY THIS IS A SEPARATE COMMIT FROM registration_allowed ABOVE: it was originally split out as
    # environments PR #42 precisely because it carries the cross-repo dependency on devops-tools —
    # burying that inside an already-reviewed PR would have made the review meaningless. #42 was
    # then merged into a STACKED branch that never itself reached `local`, so the flag was silently
    # stranded: merge commit 116e5defca2410512c198a5554a7921c4dcad86d is not an ancestor of
    # origin/local, and GitHub never retargeted the child because the parent branch was not deleted
    # on merge. This commit is the rescue. See the note in 50-conversations for the full trace.
    registration_email_as_username = true

    # 🔴 reset_password_allowed and verify_email are deliberately LEFT OFF — they are blocked on
    # SMTP, not on a decision. Verified 2026-08-24: this realm's `smtpServer` is `{}` and the shared
    # module configures no smtp_server block anywhere.
    #   • reset_password_allowed → renders "Forgot password?" leading to a form that can never
    #     deliver a reset mail. The V3 `/login/help` screen assumes this works; enabling it now
    #     would make the screen reachable and non-functional, which is worse than absent.
    #   • verify_email → hands every new registrant a VERIFY_EMAIL action satisfied only by an
    #     email that never arrives, locking them out of the account they just created. With
    #     registration now ON, enabling this without SMTP would break sign-up entirely.
    # Both become one-line changes once a mail server exists. Until then, note the accepted
    # consequence of registration-without-verification below.
    #
    # ⚠️ ACCEPTED FOR DEV, NOT FOR PROD: open registration + no email verification means anyone can
    # create an account claiming ANY address, unverified. Contained here because this is a lab realm
    # and Google remains trust_email = false (so a brokered login cannot silently inherit an account
    # by matching an unverified address). Do NOT copy this pairing into stg/prod — those need SMTP
    # and verify_email first.

    # ── Branded login theme (spec 067 / SCRUM-245, T053) ────────────────────────────────────────
    # ✅ ENABLED — this is STEP 3 of 3. The ordering below is kept because it is still the
    # procedure for stg and prod, and because it explains why this line may not be moved earlier.
    #
    #   1. publish ghcr.io/fitmate-platform/fitmate-keycloak:<sha>   (FITMate repo, `make deploy`)
    #   2. uncomment `image` in on-prem/fitmate/shared/ops-tools/terragrunt.hcl, apply, and wait
    #      for keycloak-0 to be Ready ON THAT IMAGE
    #   3. uncomment the line below, apply
    #
    # Doing 3 before 2 is NOT caught by anything. Keycloak does not validate theme names: the realm
    # accepts `fitmate`, the apply is green, and the server silently falls back to the default theme
    # at render time — a login page byte-identical to today. The failure looks exactly like success.
    #
    # `fitmate` is the theme's declared NAME (META-INF/keycloak-themes.json inside the JAR), not the
    # JAR filename. Verified 2026-08-26 against the built artifact: one theme, `fitmate`, providing
    # the `login` type only.
    #
    # ⚠️ account_theme / email_theme stay CLASSIC and are deliberately not exposed by the shared
    # module — the JAR carries login templates only, so pointing them here would break those pages.
    #
    # ACCEPTANCE TEST (the only one that counts — a green apply does not):
    #   curl -s https://auth-dev.fitmate.me/realms/fitmate-dev/protocol/openid-connect/auth \
    #     -d 'client_id=fitmate-website' --get -d 'response_type=code' \
    #     -d 'redirect_uri=https://web-dev.fitmate.me' | grep -o '/resources/[^"]*/login/[a-z0-9.-]*'
    #   BEFORE: /resources/<hash>/login/keycloak.v2      AFTER: /resources/<hash>/login/fitmate
    login_theme = "fitmate"

    # ── Internationalization (SCRUM-245 blocker, spec 067) ──────────────────────────────────────
    # Vietnamese-first, English secondary — the same ordering as Principle III (vi-VN complete, en
    # secondary). PARAMETERISED PER ENV: this is the shared module's `realm.internationalization`
    # object, defaulting to null, so stg and prod stay i18n-disabled until each adds its own block.
    # Do not move this to env.hcl — the realm's shape is a per-realm decision, not a per-env constant.
    #
    # WHY THIS IS INFRA WORK AND NOT THEME WORK: measured on the live login page 2026-08-25,
    # `document.documentElement.lang` was "en" and there was NO `#kc-locale` element in the DOM at
    # all. Keycloak renders that dropdown only when the realm has i18n enabled with >1 supported
    # locale — with i18n off, the control is never emitted and no theme can add it back. The branded
    # theme (SCRUM-245) styles a switcher that, until this applies, does not exist to style.
    #
    # TWO locales, not one, is deliberate: a single-entry list enables i18n and translates the pages
    # but renders no switcher, which is indistinguishable from a theme that forgot it.
    #
    # ✅ VERIFIED the translations actually exist in the running image before enabling this — the
    # failure mode is that a locale applies cleanly and every string still renders in English,
    # because Keycloak's `vi` bundle ships in the `resources-community` overlay that Red Hat builds
    # and `-DskipCommunityTranslations` builds omit. This cluster runs the UPSTREAM image
    # quay.io/keycloak/keycloak:26.7.0
    # (sha256:0f198be292568439d700cdbfb893e69a6009bb43a94a06a945b1d3d506c76b13), whose
    # org.keycloak.keycloak-themes-26.7.0.jar contains
    # theme/base/login/messages/messages_vi.properties at 35,360 bytes / 498 keys vs 500 for
    # messages_en.properties — including doLogIn=Đăng nhập and usernameOrEmail=Tên người dùng hoặc
    # email. The only two untranslated keys are delegationScopeConsentText and didExistsMessage,
    # neither of which appears on the login form. So no message-bundle vendoring is needed here.
    # 🔴 Re-check this if the image is ever switched to registry.redhat.io/rhbk/* or to a custom build.
    internationalization = {
      supported_locales = ["vi", "en"]
      default_locale    = "vi"
    }

    # Services gate on realm_access.roles.
    # NOTE: role is "administrator", NOT "admin" — Keycloak 26.4.0+ has an FGAP regression that blocks
    # updating a realm role literally named "admin" (403), even for a super-admin. The FitMate services
    # must gate on `administrator` in realm_access.roles. (keycloak/keycloak#43579, #44371)
    roles = ["trainee", "trainer", "administrator", "super_admin"]

    clients = concat([
      {
        client_id                    = "fitmate-website"
        name                         = "FITMate Website (BFF)"
        access_type                  = "CONFIDENTIAL" # issues a client_secret (Auth.js BFF holds it)
        standard_flow_enabled        = true           # Authorization Code
        direct_access_grants_enabled = false
        pkce_code_challenge_method   = "S256"
        # ── Redirect URIs: the DEPLOYED dev origin, alongside the local one (spec 066 T088) ──────
        # Keycloak matches redirect_uri EXACTLY against this allowlist. Auth.js does not guess the
        # callback from X-Forwarded-* — it rewrites every request's origin to AUTH_URL
        # (`reqWithEnvURL`), so the callback it sends is deterministically AUTH_URL + the provider
        # path. fitmate-gitops apps/website/dev/values.yaml:72 sets
        #     AUTH_URL: https://web-dev.fitmate.me
        # (merged, PR #82), which makes the deployed callback exactly the URI added below.
        #
        # Verified against the live realm 2026-08-24: only the localhost URI was registered, so
        # https://web-dev.fitmate.me/api/auth/callback/keycloak returned HTTP 400
        # "Invalid parameter: redirect_uri". That failure is 100% of sign-ins on the FIRST deployed
        # rollout, and it surfaces on Keycloak's OWN error page while the website pod sits
        # 1/1 Running with clean logs — so it reads as a website bug and is not one.
        #
        # localhost:3000 is KEPT, not replaced: it is how the app is run against dev Keycloak
        # locally, and dropping it would trade one broken environment for another.
        valid_redirect_uris = [
          "http://localhost:3000/api/auth/callback/keycloak",
          "https://web-dev.fitmate.me/api/auth/callback/keycloak",
          # ── Internal lab origin (IN-28) ────────────────────────────────────────────────────
          # Reached as web.dev.k3s.fitmate via /etc/hosts -> Traefik `web` listener, so a
          # browser-driving agent (chrome-devtools-mcp) never traverses Cloudflare and never
          # meets the Access interstitial that gates web-dev.fitmate.me.
          #
          # http:// IS DELIBERATE and must match the gitops AUTH_URL byte-for-byte. Nothing
          # serves TLS for a .k3s.fitmate name (cert-manager can only issue for real public
          # DNS), and Auth.js derives its cookie prefixes from AUTH_URL's SCHEME: an https
          # AUTH_URL emits __Host-/__Secure- cookies, which a browser REFUSES to store over a
          # plain-http origin. Measured 2026-08-26 against the running pod:
          #   POST /api/auth/signin/keycloak over http with AUTH_URL=https
          #   -> 302 /api/auth/signin?error=MissingCSRF   (cookie never stored, never returned)
          # That failure shows a Keycloak-free error page while the pod sits 1/1 Running, so it
          # reads as an app bug. Scheme parity here is what prevents it.
          "http://web.dev.k3s.fitmate/api/auth/callback/keycloak",
        ]
        # Post-logout is a SEPARATE allowlist in Keycloak 26 — a host valid for login is NOT
        # thereby valid for logout. Omitting it leaves sign-in working and sign-out failing with
        # "Invalid parameter: post_logout_redirect_uri", which is the harder bug to attribute.
        valid_post_logout_redirect_uris = [
          "http://localhost:3000",
          "https://web-dev.fitmate.me",
          # A host valid for LOGIN is not thereby valid for LOGOUT (separate allowlist in KC 26).
          # Omitting this leaves sign-in working and sign-out failing with
          # "Invalid parameter: post_logout_redirect_uri" — the harder half to attribute.
          "http://web.dev.k3s.fitmate",
        ]
        # web_origins is CORS, and the BFF flow does not strictly need it: Auth.js performs the
        # code exchange server-side (Node -> Keycloak), and logout is a browser NAVIGATION, not an
        # XHR. Kept at parity with localhost so the two origins do not differ for an unstated
        # reason — safe to drop both if a reviewer prefers strict least-privilege here.
        web_origins = [
          "http://localhost:3000",
          "https://web-dev.fitmate.me",
          # Kept at parity with the other two lists so the three do not diverge for an unstated
          # reason. The BFF flow does not strictly need CORS (code exchange is server-side).
          "http://web.dev.k3s.fitmate",
        ]
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
      {
        # ── admin panel token-handler BFF (ADR-066 / SCRUM-323 / spec 071) ────────────────────
        # The BROWSER leg of admin-service. admin-service runs the authorization-code + PKCE
        # exchange SERVER-SIDE with this client and hands the browser an HttpOnly cookie; the
        # access token never enters the browser (RFC 10017 §6.1).
        #
        # ⚠️ THIS IS DELIBERATELY A SECOND CLIENT, NOT `standard_flow_enabled = true` ON
        #    `fitmate-admin-backend` ABOVE. The obvious "saving" of reusing that client is a real
        #    security regression, for four reasons — the first is decisive:
        #
        #  1. BLAST RADIUS. fitmate-admin-backend's service account holds realm-management
        #     manage-users + view-users. Merging the browser leg into it means ONE leaked secret
        #     grants both "can start a login" AND "can rewrite every user in the realm". Split, a
        #     compromise of the browser-facing secret buys only the former.
        #  2. CONTRADICTORY SETTINGS. This client needs redirect URIs, web origins, post-logout
        #     URIs and PKCE; a machine identity must have NONE of them. One resource cannot hold
        #     both without that client's own "never used in a browser" comment becoming false.
        #  3. ROLLBACK. ADR-066 states rollback is "removing one Terraform client" — true only
        #     with a sibling. Editing the shared client instead makes rollback a risky edit to a
        #     resource admin-service's Admin-API path already depends on.
        #  4. AUDIT. "Which client did this login come from" stays answerable.
        #
        # service_accounts stays OFF: this client authenticates USERS. The machine identity is
        # still fitmate-admin-backend, and admin-service holds both secrets for different jobs.
        client_id                    = "fitmate-admin-bff"
        name                         = "FITMate Admin Panel (token-handler BFF)"
        access_type                  = "CONFIDENTIAL" # secret pushed to Vault below; held server-side only
        standard_flow_enabled        = true           # Authorization Code — THE reason this client exists
        direct_access_grants_enabled = false          # no password grant
        service_accounts_enabled     = false          # NOT a machine identity — see fitmate-admin-backend
        # PKCE even though the client is confidential: RFC 9700 §2.1.1 requires it for every
        # authorization-code client, not only public ones. It binds the callback to the request
        # that started it, which a client secret alone does not do.
        pkce_code_challenge_method = "S256"

        # ── Redirect URI: admin-SERVICE's callback, NOT the SPA's ────────────────────────────
        # Under a token-handler BFF the redirect URI belongs to the SERVER that performs the code
        # exchange. The Vite SPA never receives a code and must never appear in this list.
        #
        # ⚠️ https AND admin-dev.fitmate.me — both load-bearing, neither is cosmetic:
        #   • The host is a REAL Let's Encrypt name (shared/init-resources public_host_certs), not
        #     `admin.k3s.fitmate`. Nothing can serve a trusted cert for a .k3s.fitmate name, and a
        #     plain-http origin makes the browser DROP the BFF's `Secure` session cookie — login
        #     appears to succeed and then bounces, which reads as a BFF bug and is not one. Real
        #     TLS is what lets the cookie be `Secure` in dev AND prod with no per-env weakening.
        #   • It resolves ONLY to the internal Traefik LB (no public A record, no tunnel route), so
        #     the panel stays non-internet-reachable until 2FA lands, per ADR-066.
        # Keycloak matches redirect_uri EXACTLY — scheme, host and path all count.
        #
        # 🔴 `/api/v1` IS LOAD-BEARING — do not "tidy" it away (ADR-071).
        # admin-service registers EVERY handler inside router.Group("/api/v1") (routes.go:67),
        # and the callback path is composed in Go as
        #   AuthCallbackURI = "/api/v1" + AuthGroupPath + AuthCallbackRoute
        #                   = /api/v1/admin/auth/callback          (auth_handler.go:88-95)
        # ADR-066 L67 and ADR-067 L113 both wrote this path WITHOUT the prefix; this file was
        # authored from them. ADR-071 supersedes that line — the prefix is correct, the ADRs
        # were not. A mismatch here fails on Keycloak's OWN error page and never reaches our
        # logs, so it reads as "the BFF is broken" when the BFF is fine.
        valid_redirect_uris = [
          "https://admin-dev.fitmate.me/api/v1/admin/auth/callback",
        ]
        # Post-logout is a SEPARATE allowlist in Keycloak 26 — a host valid for login is NOT
        # thereby valid for logout. Omitting it leaves sign-in working and sign-out failing with
        # "Invalid parameter: post_logout_redirect_uri", the harder half to attribute.
        #
        # 🔴 This is the LOGIN PAGE path, not the bare origin. The BFF sends
        #   post_logout_redirect_uri = <adminAuth.publicBaseURL> + frontendLoginPath
        # where frontendLoginPath = "/login" (auth_handler.go:77, used at :613). Keycloak's
        # RedirectUtils.matchesRedirects compares with String.equals when the entry carries no
        # "*", so an ORIGIN DOES NOT COVER ITS SUB-PATHS — the bare host would not match.
        # "+" is not a substitute either: it inherits valid_redirect_uris, which is the
        # CALLBACK path, not this one. `/login` is served by admin-website (pathPrefix `/`).
        valid_post_logout_redirect_uris = [
          "https://admin-dev.fitmate.me/login",
        ]
        # CORS for the SPA's XHR calls to /admin/auth/me and the rest of /admin/*. Same origin as
        # the redirect URI; the code exchange itself is server-side and needs no CORS.
        web_origins = [
          "https://admin-dev.fitmate.me",
        ]
        # CRITICAL: backend services require aud contains fitmate-backend (Keycloak default aud = account).
        audiences = ["fitmate-backend"]
      },
    ], local.e2e_clients)

    # e2e test user. firstName/lastName/email/email_verified are REQUIRED for a password-grant
    # fixture — Keycloak 26's declarative user profile otherwise triggers VERIFY_PROFILE at login and
    # the direct grant fails with "Account is not fully set up" (with an empty requiredActions list).
    users = [
      {
        # `key` pins the TERRAFORM RESOURCE ADDRESS to what state already holds
        # (`keycloak_user.main["trainee1"]`, confirmed via `terragrunt state list`), so correcting
        # `username` below does NOT move the map key and does NOT recreate the user. Without it this
        # edit reads as a rename and plans 1 destroy + 1 create — issuing a new `sub` for the e2e
        # fixture over a field Keycloak had already converged on. Do not "tidy" this to match the
        # username; it is a state address, not an identifier.
        key = "trainee1"
        # ADR-050: the email IS the identifier — there is no username at any layer. Keycloak already
        # rewrote this user's username to its email when registration_email_as_username applied, so
        # the bare "trainee1" here was the stale side of that drift, not Keycloak misbehaving.
        username       = "trainee1@fitmate.local"
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
  # 🔴 KEYED BY USERNAME, not by a friendly name: users.tf does
  # `lookup(var.user_passwords, each.value.username, "")`. When the username became the email above,
  # this key had to move with it — a stale `trainee1` key makes the lookup miss, the initial_password
  # block disappear, and the user get created with NO PASSWORD. That failure surfaces as
  # `invalid_grant / Invalid user credentials` in the e2e harness against a correctly-created user.
  # The Vault PATH keeps its own name (keycloak/fitmate/trainee1/creds) — that is storage, not identity.
  user_passwords = {
    "trainee1@fitmate.local" = dependency.vault-secrets.outputs.secrets["keycloak/fitmate/trainee1/creds"]["password"]
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
      # ADR-066 BFF client secret → ESO → the fitmate-admin-<env> namespace, alongside the
      # Admin-API secret above. Its OWN path for the same reason that one has one:
      # vault_kv_secret_v2 manages a path's WHOLE data map, so writing a second key into
      # admin/keycloak/creds would clobber KEYCLOAK_CLIENTSECRET on every apply.
      #
      # ⚠️ DISTINCT KEY NAME. admin-service will hold BOTH secrets and they are not
      # interchangeable: KEYCLOAK_CLIENTSECRET authenticates the Admin-REST machine identity,
      # KEYCLOAK_BFFCLIENTSECRET authenticates the browser login exchange. Reusing one name for
      # both is how the browser-facing secret silently acquires manage-users.
      #
      # No underscore in the key: viper binds env-overrides by exact key and the existing
      # KEYCLOAK_* keys in prod-secrets-env-inventory are unpunctuated. Do NOT rename.
      "fitmate-admin-bff" = { path = "${local.environment}/admin/keycloak/bff-creds", key = "KEYCLOAK_BFFCLIENTSECRET" }
      }, local.environment == "prod" ? {} : {
      # e2e harness secret (IN-17). Its OWN path — vault_kv_secret_v2 manages a path's whole data
      # map, so writing into an existing params path would clobber every other key there.
      # Vault, not .envrc.local: the harness runs in CI, and a hand-copied secret is one that
      # eventually gets pasted somewhere it shouldn't be.
      "fitmate-e2e-test" = { path = "${local.environment}/e2e/keycloak/creds", key = "KEYCLOAK_CLIENTSECRET" }
    })
  }
}
