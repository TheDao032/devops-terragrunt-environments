locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  account_id = "8165db744d029942b3f0f344f75c189d"
}

# Local state backend (IN-12). This stack deliberately does NOT include root.hcl — it has no
# kube/Vault dependency — so it would otherwise get NO backend at all and keep writing state into
# .terragrunt-cache, which is the very thing IN-12 removes. Without this, deleting the cache makes
# Terraform offer to recreate live Cloudflare tunnels, DNS records and Access apps.
include "backend_local" {
  path = find_in_parent_folders("backend-local.hcl")
}

terraform {
  source = "../../../../../devops-terraform-modules//cloud/cloudflare-access"
}

# Cloudflare-only stack — NO kube/Vault dependency, so it deliberately does NOT include root.hcl
# (whose generated providers need a reachable cluster). Generates its own scoped provider set, the
# same way prod/cloudflare-tunnel does. This means it can apply even while the cluster is down.
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
        random = {
          source  = "hashicorp/random"
          version = "~> 3.9"
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
      api_token = "${local.environment_vars.locals.cloudflare_api_token}"
    }
  EOF
}

# ORDERING-ONLY edge (`dependencies`, plural — no output fetch): the Access app is keyed by a
# hostname whose DNS record is created by this env's cloudflare-tunnel unit. Access does not consume
# its outputs, but should apply AFTER the hostname exists so `run --all` is deterministic.
dependencies {
  paths = ["../cloudflare-tunnel"]
}

inputs = {
  account_id       = local.account_id
  allowed_emails   = ["nthedao2705@gmail.com"]
  session_duration = "24h"
  app_name_prefix  = "fitmate-dev · "

  # ── GATED, unlike prod's auth host (IN-15) ────────────────────────────────────────────────────
  # prod deliberately leaves auth.fitmate.me public — it is customer-facing. That reasoning does NOT
  # transfer to dev: its only users are us, it holds seeded test users, and it is the env most
  # likely to be running an unpatched Keycloak mid-upgrade. Cost is one Cloudflare login per
  # session_duration (24h).
  #
  # ⚠️ Gating does NOT break the Google/Facebook login flow. The provider's redirect back to
  # .../broker/google/endpoint is an ordinary browser navigation on the SAME hostname, so it still
  # carries the CF_Authorization cookie set seconds earlier — Access passes it straight through.
  #
  # ⚠️ Nor does it break token validation. Services fetch JWKS over CLUSTER DNS
  # (keycloak-service.keycloak.svc.cluster.local:8080), never via Cloudflare, so that backchannel
  # call never meets Access. That issuer/JWKS split already exists for another reason — see the
  # KEYCLOAK_JWKSURL note in env.hcl — and is exactly what makes gating safe here.
  #
  # Real cost: a future automated e2e test driving a browser login against dev needs an Access
  # SERVICE TOKEN, not just user credentials.
  #
  # To make it public: delete the entry and apply. Access applications destroy cleanly, and routing
  # is unaffected — reachability lives in cloudflare-tunnel, authorization lives here.
  apps = {
    "auth-dev.fitmate.me" = { name = "Keycloak dev" }

    # ── The dev WEBSITE (B-W12) ───────────────────────────────────────────────────────────────
    # Same reasoning as the auth host above — its only users are us and it serves seeded data —
    # but here there is code evidence, not just posture. `src/app/robots.ts` is ENVIRONMENT-BLIND:
    # no host check, no NODE_ENV check, identical output everywhere —
    #     allow: ["/", "/trainers"]
    # and src/app/layout.tsx sets `robots: { index: true, follow: true }` at the ROOT layout.
    # `createPrivateMetadata` sets index:false, but only on the private pages; the PUBLIC marketing
    # routes are the indexable ones — and /trainers is exactly the seeded fake-trainer data.
    #
    # So an ungated web-dev does not merely PERMIT crawling, it actively INVITES it, onto a public
    # duplicate of the marketing site backed by fake data. De-indexing that afterwards costs far
    # more than this entry.
    #
    # ⚠️ Gating adds NO testing barrier that does not already exist: auth-dev above is gated to the
    # same single email, so anyone who can test a sign-in today is already that identity.
    #
    # ⚠️ And it does NOT break the login flow. Verified 2026-08-24, both hops:
    #   • Browser: the Auth.js callback (/api/auth/callback/keycloak) is an ordinary navigation on
    #     THIS hostname, so it carries the CF_Authorization cookie set seconds earlier — the same
    #     property that makes the Google broker callback work on the auth host.
    #   • SERVER-SIDE: Auth.js exchanges the code from inside the Next.js pod against
    #     AUTH_KEYCLOAK_ISSUER (https://auth-dev.fitmate.me/...), which is a NON-browser call and
    #     would be challenged by Access — except IN-16's split-horizon DNS rewrites that name
    #     in-cluster. Confirmed from a pod: auth-dev.fitmate.me -> 10.43.85.195 = Traefik's
    #     ClusterIP, so the token exchange never reaches Cloudflare at all.
    #     Without that split horizon this WOULD fail; do not remove coredns-custom.
    #
    # No split-horizon entry is needed for web-dev itself — nothing in-cluster calls the website by
    # hostname (AUTH_URL is used to CONSTRUCT URLs, not to self-call).
    #
    # To make it public: delete this entry and apply. Reachability is unaffected either way — it
    # lives in ../cloudflare-tunnel.
    "web-dev.fitmate.me" = { name = "Website dev" }
  }
}
