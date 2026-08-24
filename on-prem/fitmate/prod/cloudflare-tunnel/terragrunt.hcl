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
  ]
}
