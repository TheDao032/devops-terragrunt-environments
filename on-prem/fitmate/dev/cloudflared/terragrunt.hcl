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
# the tunnel flips Inactive → Healthy and auth-dev.fitmate.me starts serving.
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
  namespace    = "cloudflared-dev"
  tunnel_name  = "fitmate-dev"
  tunnel_token = dependency.cloudflare_tunnel.outputs.tunnel_token

  # 1 replica (prod runs 2). This is a dev/stg edge for a handful of users, and the cluster is
  # memory-constrained — see IN-13's capacity note before raising it.
  replicas = 1
}
