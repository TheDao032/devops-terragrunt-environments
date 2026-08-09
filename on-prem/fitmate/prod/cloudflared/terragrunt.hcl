locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/cloudflared"
}

# Deploys INTO the cluster (kubernetes provider from root.hcl) → the cluster must be UP. Unlike the
# cloudflare-tunnel unit (Cloudflare-only, cluster-independent), this one includes root.hcl for the
# kube provider. Apply ORDER: cloudflare-tunnel (creates the tunnel + token) → cloudflared (this).
# Once cloudflared connects, the tunnel flips Inactive → Healthy and *.fitmate.me serves.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "kube" {
  path = find_in_parent_folders("kube.hcl")
}

# The run token comes from the Phase-2 cloudflare-tunnel output (sensitive). mocks let plan/validate
# run before that unit is applied.
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
  namespace    = "cloudflared"
  tunnel_name  = "fitmate-prod"
  tunnel_token = dependency.cloudflare_tunnel.outputs.tunnel_token
  replicas     = 2
}
