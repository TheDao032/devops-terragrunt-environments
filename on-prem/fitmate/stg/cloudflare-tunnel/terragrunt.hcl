locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  # Same Cloudflare account + zone as every other env — only the TUNNEL is per-env.
  account_id = "8165db744d029942b3f0f344f75c189d"
  zone_id    = "71113800c684f8e9bd342c4545f9aecd"
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
  ]
}
