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
  }
}
