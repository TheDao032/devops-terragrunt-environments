locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  # Non-secret Cloudflare IDs for fitmate.me (the CLOUDFLARE_API_TOKEN secret comes from the env).
  account_id = "8165db744d029942b3f0f344f75c189d"
  zone_id    = "71113800c684f8e9bd342c4545f9aecd"

  # All public hostnames hand off to Traefik (the k3s ingress), which routes by Host header to the
  # right Service via its Ingress. CONFIRMED 2026-08-03: Traefik runs in ns `traefik` (svc `traefik`,
  # port 80), NOT the k3s-default kube-system. cloudflared connects here; the fitmate-ingress unit
  # adds the matching `*.fitmate.me` Ingresses that Traefik routes to each service.
  traefik = "http://traefik.traefik.svc.cluster.local:80"
}

terraform {
  source = "../../../../../devops-terraform-modules//cloud/cloudflare-tunnel"
}

# Cloudflare-only stack — NO kube/Vault dependency, so it deliberately does NOT include root.hcl
# (whose generated kube/helm/vault providers need a reachable cluster + pull in the whole cluster
# provider set). So it generates its OWN provider set the repo way (terragrunt-generated, NOT a
# module versions.tf), scoped to just cloudflare + random. Local state by default (prod = local).
# => this apply creates the tunnel + DNS on Cloudflare's side and can run even before the cluster is up.
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
      # api_token from env.hcl's cloudflare_api_token local (= CLOUDFLARE_API_TOKEN env, .envrc.local).
      api_token = "${local.environment_vars.locals.cloudflare_api_token}"
    }
  EOF
}

inputs = {
  account_id  = local.account_id
  zone_id     = local.zone_id
  tunnel_name = "fitmate-prod"

  # hostname -> internal service. app + auth are public; admin surfaces (vault/traefik/kafka-ui/argocd)
  # get gated at the edge by Cloudflare Access in Phase 6. All hand off to Traefik by Host header, so
  # each host needs a matching Traefik Ingress (add the fitmate.me host to each service's Ingress).
  routes = [
    { hostname = "fitmate.me", service = local.traefik },          # website (apex)
    { hostname = "www.fitmate.me", service = local.traefik },      # www -> apex
    { hostname = "api.fitmate.me", service = local.traefik },      # api-gateway
    { hostname = "auth.fitmate.me", service = local.traefik },     # Keycloak (public auth)
    { hostname = "vault.fitmate.me", service = local.traefik },    # Vault UI    (Access-gated)
    { hostname = "traefik.fitmate.me", service = local.traefik },  # Traefik dash (Access-gated)
    { hostname = "kafka-ui.fitmate.me", service = local.traefik }, # kafka-ui    (Access-gated)
    { hostname = "argocd.fitmate.me", service = local.traefik },   # ArgoCD      (Access-gated)

    # ── Per-env Keycloak hosts (IN-15 phase 3) ───────────────────────────────────────────────────
    # ⚠️ This unit lives under prod/ but is CLUSTER-WIDE in practice: five of the hostnames above
    # already front shared singletons (Vault, Traefik, kafka-ui, ArgoCD, Keycloak) that serve all
    # three envs. There is ONE cluster, ONE Traefik and ONE tunnel — so dev/stg get hostnames HERE
    # rather than their own tunnel + connector. Three connectors would be 6 pods on a cluster
    # already at its memory ceiling (IN-13), all terminating at the same Traefik.
    # Re-tiering this unit to shared/ is the correct cleanup but belongs to IN-12: its state lives
    # in .terragrunt-cache and the tunnel CONFIG resource is create-only (destroy is a silent no-op
    # that orphans ingress config), so moving state must happen after the backend migration.
    #
    # DECIDED 2026-08-22 — one shared tunnel, NOT per-env tunnels. Why the hostnames can't just live
    # in dev/env.hcl and stg/env.hcl: cloudflare_zero_trust_tunnel_cloudflared_config is a SINGLE
    # resource holding the whole ingress list, so a tunnel has exactly one Terraform owner. Two
    # units managing the same tunnel would overwrite each other's list on every apply. The only way
    # to give dev/stg their own folders is to give them their own TUNNELS — four pipes terminating
    # at the same Traefik, which routes by Host anyway, so the isolation would be illusory.
    # REVISIT IF prod moves to its own cluster: per-env tunnels stop being a preference and become
    # forced, and this unit has to be split regardless.
    #
    # WHY THESE HOSTS EXIST AT ALL: one Keycloak serves every realm, and with hostname_dynamic
    # (phase 2) it derives `iss` from X-Forwarded-Host. So each env needs its OWN public hostname to
    # stamp its own issuer:
    #   auth.dev.fitmate.me -> iss https://auth.dev.fitmate.me/realms/fitmate-dev
    # Without that, Google/Facebook cannot register a broker callback at all — both require https,
    # and keycloak.k3s.fitmate is plain HTTP on a private host (this is what blocks IN-14).
    #
    # Adding a hostname here also creates its proxied CNAME automatically (one per ingress entry).
    # Both are ACCESS-GATED — see the cloudflare-access unit. A dev IdP holds seeded test users and
    # is the env most likely to be running an unpatched Keycloak mid-upgrade; it has exactly one
    # class of user (us), so there is no reason for the internet to reach its login page.
    { hostname = "auth.dev.fitmate.me", service = local.traefik }, # Keycloak dev (Access-gated)
    { hostname = "auth.stg.fitmate.me", service = local.traefik }, # Keycloak stg (Access-gated)
  ]
}
