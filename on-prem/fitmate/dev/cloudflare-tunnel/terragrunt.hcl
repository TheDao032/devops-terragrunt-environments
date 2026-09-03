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
  tunnel_name = "fitmate-dev"

  # ── Per-env tunnel (IN-15, decided 2026-08-22) ────────────────────────────────────────────────
  # Each env owns its OWN tunnel rather than sharing prod's. Two reasons that actually matter:
  #
  #  1. A tunnel's ingress is a SINGLE Terraform resource holding the whole hostname list
  #     (cloudflare_zero_trust_tunnel_cloudflared_config), so it has exactly one owner. Sharing one
  #     tunnel across envs would mean dev/ and prod/ overwriting each other's list on every apply.
  #     Per-env tunnels are the only way each env folder can own its own hostnames.
  #  2. Blast radius: a leaked dev token can only advertise dev hostnames.
  #
  # Cost accepted: one extra connector Deployment per env (see ../cloudflared, 1 replica).
  #
  # WHY THIS HOSTNAME EXISTS: one Keycloak serves every realm, and with hostname_dynamic it derives
  # `iss` from X-Forwarded-Host — so each env needs its own public host to stamp its own issuer:
  #     auth-dev.fitmate.me -> iss https://auth-dev.fitmate.me/realms/fitmate-dev
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
  #
  # ── web-dev.fitmate.me: the WEBSITE (spec 066 T088 / SCRUM-238) ───────────────────────────────
  # Layer 1 of three. B-W09 is not one blocker but three, each hiding the next:
  #     1. DNS          — this entry; the hostname did not resolve AT ALL (dig returned nothing)
  #     2. tunnel route — this entry; the tunnel advertised only auth-dev
  #     3. Keycloak     — the redirect_uri allowlist (environments PR #40)
  # Fixing any one alone just moves the failure. This unit closes 1 and 2 together, because a
  # cloudflared ingress entry creates its proxied CNAME as a side effect.
  #
  # ⚠️ Same flat-name rule as auth-dev: `web-dev`, NOT `web.dev`. See the Universal SSL note above —
  # a second label is outside `*.fitmate.me` and fails the TLS handshake with everything healthy.
  #
  # Points at Traefik's :80 (the `web` entrypoint), which is the ONLY listener tunnel traffic ever
  # reaches. Traced, not assumed: Service traefik:80 name=`web` -> targetPort `web` -> Gateway
  # listener `web` :8000. The `websecure` :8443 listener is not on this path — the keycloak route's
  # extra websecure attachment is not what makes it work. The website chart's
  # `route.gateway.sectionName` already defaults to `web`, so it agrees.
  #
  # The public URL stays https://web-dev.fitmate.me — Cloudflare terminates TLS at the edge, so
  # this plain-HTTP in-cluster hop does not change the origin Auth.js is pinned to via AUTH_URL.
  #
  # ⚠️ EXPECT 404 UNTIL THE APP IS SYNCED. Verified 2026-08-24: namespace fitmate-website-dev does
  # not exist and the overlay still has route.enabled: false. Traefik has no HTTPRoute for this
  # Host, so the tunnel forwards into a 404. That is the correct order — reachability first, then
  # the app — and the 404 is the signal the tunnel works. It is NOT a routing bug to chase.
  #
  # ⚠️ DELIBERATELY NOT Access-gated (../cloudflare-access lists hostnames explicitly, so this one
  # is public by omission — reachability lives here, authorization lives there). That is a SECURITY
  # DECISION, not a default: dev's auth host IS gated on the reasoning "its only users are us."
  # The same argument applies to a dev website holding seeded data, and it is raised with the app
  # track rather than settled here. Gating it later is one line in that unit.
  #
  # ℹ️ Note for whoever tests the login: auth-dev.fitmate.me IS Access-gated to a single email, so
  # the sign-in redirect meets a Cloudflare challenge BEFORE Keycloak's login page. Expected, and
  # it means a test with any other identity fails at Cloudflare rather than at Keycloak.
  # ── api-dev.fitmate.me: the PUBLIC API SURFACE (spec 073 FR-026 / SCRUM-335, ADR-058) ─────────
  # ADR-058 settles the topology: the Flutter app calls the API DIRECTLY over a public HTTPS host
  # (RFC 8252 — a native app has an OS keystore, so it does not need, and must not be given, the
  # browser's BFF). ONE host, PATH-routed — `api-dev.fitmate.me/api/v1/{service}/...` — explicitly
  # NOT per-service subdomains. This entry is the hostname half of that; the HTTPRoute that gives it
  # a backend is spec 073's application work and does not exist yet.
  #
  # ⚠️ Same flat-name rule as auth-dev/web-dev: `api-dev`, NOT `api.dev`. See the Universal SSL note
  # above — a second label falls outside `*.fitmate.me` and fails the TLS handshake outright.
  #
  # ── WHY THERE IS NO cert-manager CERTIFICATE HERE ────────────────────────────────────────────
  # This host needs NOTHING in shared/init-resources `public_host_certs`, and no coredns rewrite.
  # Traced against the three patterns actually running on this cluster (verified live 2026-09-03):
  #
  #   auth-dev   tunnel + cert + coredns rewrite   parentRefs: web AND websecure
  #              -> has a cert ONLY because in-cluster pods (the website's Auth.js code exchange
  #                 and token refresh) call it BY PUBLIC NAME over trusted TLS via split horizon.
  #   admin-dev  cert + coredns rewrite, NO tunnel parentRefs: websecure
  #              -> not public at all (ADR-066); cert exists for the browser's `Secure` cookie.
  #   web-dev    tunnel ONLY, no cert, no rewrite  parentRefs: web
  #              -> Cloudflare terminates TLS at the edge with the free Universal SSL cert
  #                 (CN=fitmate.me, SANs fitmate.me + *.fitmate.me); the origin hop is plain HTTP.
  #
  # api-dev is the **web-dev** case exactly: its callers are on the INTERNET (the Flutter app), and
  # nothing inside the cluster resolves it — service-to-service traffic uses cluster FQDNs and the
  # website uses its own BFF. No in-cluster caller means no split horizon, which means no need for a
  # trusted cert on Traefik. Confirmed: there is no `web-dev-fitmate-me-tls` Certificate and web-dev
  # serves valid TLS anyway.
  #
  # 🔴 THEREFORE spec 073's HTTPRoute MUST attach with `sectionName: web`, matching the website's.
  #    Attaching it to `websecure` instead makes Traefik answer that SNI with its DEFAULT cert —
  #    and because the tunnel's origin hop is plain HTTP :80, a websecure-only route also has no
  #    listener on the path traffic actually arrives on. Both failures look like a routing bug.
  #
  # ── 🔴 DELIBERATELY *NOT* ACCESS-GATED — THIS IS A SECURITY DECISION, NOT AN OVERSIGHT ───────
  # auth-dev and web-dev are BOTH gated in ../cloudflare-access on the reasoning "its only users are
  # us." That reasoning CANNOT transfer here: Cloudflare Access is an interactive browser
  # interstitial, and a native Flutter client cannot complete it. Gating this host would not harden
  # the API, it would make spec 073 impossible — the app would receive the Access login HTML instead
  # of JSON. (A service token is the only machine path through Access, and shipping one inside a
  # distributed mobile binary is strictly worse than not gating.)
  #
  # So authorization for this host is the API's OWN bearer-token auth, and nothing else. That raises
  # two obligations that live in spec 073's HTTPRoute, NOT here — flagged because THIS entry is what
  # makes them internet-reachable:
  #   1. 🔴 `/internal/v1/*` MUST NOT be routed onto this host. It carries UNAUTHENTICATED
  #      withdrawal approval. Route `/api/v1` only — a bare `/` prefix would expose it.
  #   2. `/health` is probed in-cluster and must not be edge-reachable either.
  #
  # ⚠️ EXPECT 404 UNTIL SPEC 073 SYNCS ITS HTTPRoute. Verified 2026-09-03: no HTTPRoute anywhere on
  # the cluster claims this hostname, so the tunnel will forward into Traefik's 404. That is the
  # correct order — reachability first, then the app — and the 404 is the signal the tunnel works.
  # It is NOT a routing bug to chase. It also means nothing can silently lose a Gateway API conflict
  # on oldest-creation-timestamp here: the hostname is unclaimed.
  routes = [
    { hostname = "auth-dev.fitmate.me", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "web-dev.fitmate.me", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "api-dev.fitmate.me", service = "http://traefik.traefik.svc.cluster.local:80" },
  ]
}
