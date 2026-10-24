locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/cloudflared"
}

# Deploys INTO the cluster (kubernetes provider from root.hcl) → the cluster must be UP. Unlike the
# sibling cloudflare-tunnel unit (Cloudflare-only, cluster-independent), this one includes root.hcl.
# Apply ORDER: cloudflare-tunnel (creates tunnel + token) → cloudflared (this). Once it connects,
# the tunnel flips Inactive → Healthy and auth-stg.fitmate.me starts serving.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "kube" {
  path = find_in_parent_folders("kube.hcl")
}

# Run token comes from this env's tunnel (sensitive). Mocks let plan/validate run before it exists.
dependency "cloudflare_tunnel" {
  config_path = "../cloudflare-tunnel"
  mock_outputs = {
    tunnel_id    = "00000000-0000-0000-0000-000000000000"
    tunnel_cname = "mock.cfargotunnel.com"
    tunnel_token = "mock-token"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  # OWN namespace per env — prod uses `cloudflared`, so a shared name would collide and the three
  # connectors would fight over one Deployment.
  namespace    = "cloudflared-stg"
  tunnel_name  = "fitmate-stg"
  tunnel_token = dependency.cloudflare_tunnel.outputs.tunnel_token

  # 1 replica (prod runs 2). This is a dev/stg edge for a handful of users, and the cluster is
  # memory-constrained — see IN-13's capacity note before raising it.
  #
  # 🔴 PARKED AT 0 — 2026-10-24. Every stg WORKLOAD was scaled to 0 in gitops #554
  # (1fa53c2e) once the full money loop was proven end to end on this environment.
  # This connector was the last Running pod in stg: a tunnel with nothing behind it.
  #
  # 0 IS AN OVERRIDE, NOT A DELETION — and here that matters more than usual: the
  # module's `replicas` variable DEFAULTS TO 2 (shared/cloudflared/variables.tf:19).
  # Removing this line would not park the tunnel, it would DOUBLE it.
  #
  # WHAT THIS BREAKS, DELIBERATELY: auth-stg / web-stg / api-stg .fitmate.me stop
  # answering — Cloudflare returns its own 1033 'tunnel not found' page instead of
  # routing into a cluster with no backends. The DNS records, the tunnel itself and
  # its route table are untouched and stay in Cloudflare.
  #
  # TO RESUME: set this back to 1 and apply, together with the gitops PR that
  # restores the six stg workloads to 1. Order does not matter; a connector with no
  # backends 502s, and backends with no connector are simply unreachable.
  replicas = 0
}
