locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  account_id = "8165db744d029942b3f0f344f75c189d"
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
  app_name_prefix  = "fitmate-stg · "

  # ── GATED, unlike prod's auth host (IN-15) ────────────────────────────────────────────────────
  # prod deliberately leaves auth.fitmate.me public — it is customer-facing. That reasoning does NOT
  # transfer to stg: its only users are us, it holds seeded test users, and it is the env most
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
  # Real cost: a future automated e2e test driving a browser login against stg needs an Access
  # SERVICE TOKEN, not just user credentials.
  #
  # To make it public: delete the entry and apply. Access applications destroy cleanly, and routing
  # is unaffected — reachability lives in cloudflare-tunnel, authorization lives here.
  apps = {
    "auth-stg.fitmate.me" = { name = "Keycloak stg" }
  }
}
