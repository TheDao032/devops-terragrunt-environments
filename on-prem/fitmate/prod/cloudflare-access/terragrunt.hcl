locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  account_id = "8165db744d029942b3f0f344f75c189d"
}

terraform {
  source = "../../../../../devops-terraform-modules//cloud/cloudflare-access"
}

# Cloudflare-only stack (no cluster) — same pattern as cloudflare-tunnel: does NOT include root.hcl,
# generates its own cloudflare provider + versions. Local state by default.
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.11.2, < 2.0.0"
      required_providers {
        cloudflare = {
          source  = "cloudflare/cloudflare"
          version = "~> 5.23"
        }
      }
    }
  EOF
}

generate "provider_cloudflare" {
  path      = "provider-cloudflare.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "cloudflare" {
      # api_token from env.hcl's cloudflare_api_token local (= CLOUDFLARE_API_TOKEN env, .envrc.local).
      api_token = "${local.environment_vars.locals.cloudflare_api_token}"
    }
  EOF
}

# ORDERING-ONLY edge (`dependencies`, plural — no output fetch): Access apps are keyed by hostname
# (vault.fitmate.me, traefik.fitmate.me) whose DNS records are created by cloudflare-tunnel. Access
# doesn't consume the tunnel's outputs, but it should apply AFTER those hostnames exist so `run --all`
# is deterministic. Both are cloudflare-only units (no root.hcl) — a pure ordering edge is correct here.
dependencies {
  paths = ["../cloudflare-tunnel"]
}

inputs = {
  account_id       = local.account_id
  allowed_emails   = ["nthedao2705@gmail.com"]
  session_duration = "24h"
  app_name_prefix  = "fitmate-prod · "

  # Admin hosts gated behind Access (identity login at the edge). Public hosts (fitmate.me/api/auth)
  # are intentionally NOT here. Add argocd/kafka-ui once their services + fitmate-ingress routes exist.
  apps = {
    "vault.fitmate.me"   = { name = "Vault" }
    "traefik.fitmate.me" = { name = "Traefik dashboard" }
    "argocd.fitmate.me"  = { name = "ArgoCD" }
    # auth.fitmate.me (Keycloak) is intentionally NOT gated — it's the login provider, must be public.
    # "kafka-ui.fitmate.me" = { name = "kafka-ui" }   # no kafka-ui service yet — deferred

    # ── Per-env Keycloak (IN-15 phase 3) — GATED, unlike prod auth above ─────────────────────────
    # The note above is right for PRODUCTION auth: it is customer-facing, so it must be public.
    # That reasoning does not transfer to a dev/stg IdP, whose only users are us. Those realms hold
    # seeded test users and are the most likely to be running an unpatched Keycloak mid-upgrade, so
    # there is no reason for the internet to reach their login page. Cost: one Cloudflare login per
    # session_duration (24h).
    #
    # ⚠️ Gating does NOT break the Google/Facebook login flow. Google's redirect back to
    # .../broker/google/endpoint is an ordinary browser navigation on the SAME hostname, so it still
    # carries the CF_Authorization cookie set seconds earlier at the start of the flow — Access
    # passes it straight through.
    #
    # ⚠️ Nor does it break token validation. Services fetch JWKS over CLUSTER DNS
    # (keycloak-service.keycloak.svc.cluster.local:8080), never through Cloudflare, so that
    # server-to-server call never meets Access. That issuer/JWKS split already exists for a
    # different reason — see the KEYCLOAK_JWKSURL note in each env.hcl — and is precisely what makes
    # gating safe here. If a backchannel caller ever DID come via the public host, it would receive
    # Cloudflare's login page instead of JWKS and signature verification would fail.
    #
    # Real cost to accept: a future automated e2e test driving a browser login against dev will need
    # an Access SERVICE TOKEN, not just user credentials.
    #
    # To make either host public again: delete its line and apply. Access applications destroy
    # cleanly (unlike the tunnel's create-only config resource), and routing is unaffected —
    # reachability lives in the cloudflare-tunnel unit, authorization lives here.
    "auth.dev.fitmate.me" = { name = "Keycloak dev" }
    "auth.stg.fitmate.me" = { name = "Keycloak stg" }
  }
}
