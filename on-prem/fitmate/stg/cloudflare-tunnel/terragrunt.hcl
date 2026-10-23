locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  # Same Cloudflare account + zone as every other env — only the TUNNEL is per-env.
  account_id = "8165db744d029942b3f0f344f75c189d"
  zone_id    = "71113800c684f8e9bd342c4545f9aecd"
}

# Local state backend (IN-12). This stack deliberately does NOT include root.hcl — it has no
# kube/Vault dependency — so it would otherwise get NO backend at all and keep writing state into
# .terragrunt-cache, which is the very thing IN-12 removes. Without this, deleting the cache makes
# Terraform offer to recreate live Cloudflare tunnels, DNS records and Access apps.
include "backend_local" {
  path = find_in_parent_folders("backend-local.hcl")
}

terraform {
  source = "../../../../../devops-terraform-modules//cloud/cloudflare-tunnel"
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

inputs = {
  account_id  = local.account_id
  zone_id     = local.zone_id
  tunnel_name = "fitmate-stg"

  # ── Per-env tunnel (IN-15, decided 2026-08-22) ────────────────────────────────────────────────
  # Each env owns its OWN tunnel rather than sharing prod's. Two reasons that actually matter:
  #
  #  1. A tunnel's ingress is a SINGLE Terraform resource holding the whole hostname list
  #     (cloudflare_zero_trust_tunnel_cloudflared_config), so it has exactly one owner. Sharing one
  #     tunnel across envs would mean dev/ and prod/ overwriting each other's list on every apply.
  #     Per-env tunnels are the only way each env folder can own its own hostnames.
  #  2. Blast radius: a leaked stg token can only advertise stg hostnames.
  #
  # Cost accepted: one extra connector Deployment per env (see ../cloudflared, 1 replica).
  #
  # WHY THIS HOSTNAME EXISTS: one Keycloak serves every realm, and with hostname_dynamic it derives
  # `iss` from X-Forwarded-Host — so each env needs its own public host to stamp its own issuer:
  #     auth-stg.fitmate.me -> iss https://auth-stg.fitmate.me/realms/fitmate-stg
  #
  # ⚠️ FLAT NAME ON PURPOSE — `auth-dev`, NOT `auth.dev`. Cloudflare's free Universal SSL certificate
  # covers exactly `fitmate.me` and `*.fitmate.me`, and a wildcard matches ONE label only. A
  # multi-level name like auth.dev.fitmate.me is therefore NOT covered: Cloudflare presents no
  # certificate and the TLS handshake fails outright —
  #     curl: (35) sslv3 alert handshake failure
  #     openssl: no peer certificate available
  # with DNS, tunnel and connector all healthy, which makes it look like a routing bug. Verified
  # against the live cert: SANs are exactly DNS:fitmate.me, DNS:*.fitmate.me.
  # Covering *.dev.fitmate.me needs Advanced Certificate Manager (paid add-on). Do NOT "tidy" these
  # back to dotted subdomains without buying ACM first — the same silent TLS failure returns.
  # Google and Facebook both require https for broker callbacks, which the private plain-HTTP
  # keycloak.k3s.fitmate can never satisfy — that is what blocks IN-14.
  #
  # Traefik must ALSO accept this Host (shared/ops-tools keycloak routing.httproutes.hostnames) or
  # the tunnel forwards into a 404. Adding a hostname there is a security decision — see the note
  # in that file. Access gating lives in ../cloudflare-access.
  #
  # Adding a route here also creates its proxied CNAME automatically (one per ingress entry).
  routes = [
    { hostname = "auth-stg.fitmate.me", service = "http://traefik.traefik.svc.cluster.local:80" },
    # ── web-stg (IN-36, 2026-09-25) ───────────────────────────────────────────────────────────────
    # Added ONLY after the backend existed. Ordering is load-bearing: this entry creates a proxied
    # CNAME, so adding it first would have made web-stg.fitmate.me resolve and serve a 404 to every
    # visitor — a hostname that looks provisioned on the board and works for nobody. The note at the
    # top of this block spells out the same rule: Traefik must ALSO accept the Host or the tunnel
    # forwards into a 404.
    #
    # Verified before adding (gitops PR #401, chart fitmate-website 1.0.0):
    #   HTTPRoute `website` in ns fitmate-website-stg   hostnames ["web-stg.fitmate.me"]
    #                                                   Accepted=True  ResolvedRefs=True
    #   in-cluster curl -H "Host: web-stg.fitmate.me" http://traefik.traefik:80  -> HTTP 200
    #   negative control, Host bogus.fitmate.me                                  -> HTTP 404
    # So the 200 proves the route matched rather than a catch-all answering.
    #
    # FLAT NAME, like every host here: `web-stg`, never `web.stg`. Universal SSL covers
    # fitmate.me and *.fitmate.me only — one label — so a dotted name gets no certificate and
    # fails the TLS handshake outright while DNS, tunnel and connector all look healthy.
    { hostname = "web-stg.fitmate.me", service = "http://traefik.traefik.svc.cluster.local:80" },
    # ── api-stg (2026-10-22) — the PUBLIC API SURFACE on stg ──────────────────────────────────────
    # Mirrors api-dev (ADR-058 / spec 073 FR-026, SCRUM-335): ONE host, PATH-routed —
    # api-stg.fitmate.me/api/v1/{service}/... — explicitly NOT per-service subdomains.
    #
    # WHY IT IS NEEDED NOW: SePay delivers pay-in webhooks by HTTP POST to a public URL. gitops
    # #541 published Exact /webhooks/sepay/v1 on the stg payment HTTPRoute and wired the stg
    # SePay credentials, but the hostname did not resolve AT ALL (dig returned nothing), so
    # SePay had nowhere to deliver to. dev has had this host since 2026-09-03.
    #
    # ⚠️ ORDERING RULE (the one web-stg above records): this entry creates a proxied CNAME, so
    # adding it before a backend accepts the Host would make api-stg.fitmate.me resolve and serve
    # a 404 to everything — a hostname that looks provisioned and works for nobody.
    #
    # VERIFIED BEFORE ADDING, same evidence shape web-stg used (2026-10-22, in-cluster):
    #   HTTPRoute `payment-service` in ns fitmate-payment-stg  hostnames ["api-stg.fitmate.me"]
    #                                                          Accepted=True  ResolvedRefs=True
    #   HTTPRoute `booking-service` in ns fitmate-booking-stg  hostnames ["api-stg.fitmate.me"]
    #                                                          Accepted=True  ResolvedRefs=True
    #   curl -H "Host: api-stg.fitmate.me" http://traefik.traefik:80/api/v1/bookings  -> HTTP 401
    #   negative control, Host bogus.fitmate.me                                       -> HTTP 404
    #   positive control, Host api-dev.fitmate.me (known-good publicly)               -> HTTP 401
    # The 401 proves the route MATCHED and auth ran, rather than a catch-all answering. A 200 is
    # not available here: every path on this host requires a token.
    #
    # 🪤 Do NOT probe /api/v1/payments to check this: it is POST-only and returns 404 on DEV too,
    # which reads exactly like "the Host is not accepted". That false negative cost a detour.
    #
    # FLAT NAME: `api-stg`, never `api.stg`. Universal SSL covers fitmate.me and *.fitmate.me only
    # — one label — so a dotted name gets no certificate and fails the TLS handshake outright while
    # DNS, tunnel and connector all look healthy.
    { hostname = "api-stg.fitmate.me", service = "http://traefik.traefik.svc.cluster.local:80" },
  ]
}
