locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/netpol-baseline"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/shared/netpol-baseline?ref=${local.environment}"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# IN-40 / ADR-109 layer 1 — ingress default-deny for every FITMate namespace.
#
# 🔴 THE NAMESPACE LIST IS DERIVED FROM WHAT ACTUALLY EXISTS, not from a wish list.
# A namespace named here that does not exist yet makes kubectl_manifest fail the
# whole apply, so this list must track reality. Measured on dev 2026-10-14.
#
# When a new service is onboarded: add it here FIRST (it lands closed), then add
# its allows in fitmate-gitops platform/netpol/<env>/<service>.yaml. That order is
# the entire point of the two-layer split Dao chose — a service that is forgotten
# here is not silently open, and a service forgotten in gitops fails loudly in
# testing rather than quietly exposing a port.
# 🔴 PARKED 2026-10-14 AFTER TWO PRODUCTION FAILURES. DO NOT RE-ENABLE AS-IS.
#
# This unit applied an ingress default-deny to every fitmate namespace. It was applied
# twice and rolled back twice:
#
#   Round 1 — allowed only kube-system, but the Traefik proxy runs in a namespace called
#     "traefik" (kube-system holds only the svclb helper pods). web-dev, admin-dev and
#     web-stg all returned HTTP 502 while every pod stayed 1/1 Running. Fixed in
#     devops-terraform-modules#30.
#
#   Round 2 — with traefik allowed the public sites came back, but admin-service could no
#     longer reach trainer-service (rc=4), surfacing as
#     503 verification.service_unavailable, and the admin document review screen went down.
#     The allow-list only covered fitmate-media-dev; EVERY service calls other services and
#     none of those edges had allows.
#
# 🔴 THE ROOT CAUSE IS NOT EITHER BUG. A default-deny baseline is a FLEET-WIDE change: it is
# correct only when EVERY real call path has an explicit allow. Both failures came from
# verifying one namespace (media-service) and generalising to eleven others.
#
# THAT PRECONDITION IS NOW MET FOR STAGING (IN-50, 2026-10-16). The stg call graph was
# measured from all five sources and every edge validated against the live cluster:
#
#   ConfigMaps      8 edges found, 4 of them ASPIRATIONAL and discarded — website-stg
#                   declares booking/inquiry/notification/payment-stg, none of which exist.
#   Secrets         0. Verified as a REAL zero, not a broken probe: the identical code finds
#                   admin-service-secrets/SERVICES_MEDIASERVICEURL on dev, and stg has 10
#                   secrets across the 4 namespaces.
#   Baked files     1 — media-stg -> trainer-stg:5001, which appears in NO kubernetes object
#                   at all (it lives in config/stg/config.yaml inside the image).
#   ServiceMonitors 0 on stg (dev has 4). The monitoring allow is therefore defensive here.
#   HTTPRoutes      1 — website-stg only. There is no api-stg host.
#
# The 5 surviving edges, and all 5 are already covered by the gitops allow-lists:
#   trainee-stg -> trainer-stg:5000 · website-stg -> media-stg:3002
#   website-stg -> trainee-stg:5000 · website-stg -> trainer-stg:5000
#   media-stg   -> trainer-stg:5001
#
# TRIALLED ON THE LIVE CLUSTER BEFORE THIS FILE CHANGED. The identical policy body was
# applied to all 4 stg namespaces: the 5 measured edges stayed rc=0, the unmeasured
# trainer-stg -> media-stg stayed rc=4 (proving the policy enforces rather than sitting
# inert), web-stg.fitmate.me returned 200 three times, and all 4 pods stayed 1/1. The trial
# policies were then deleted and the change shipped here as code.
#
# WHAT STILL PROTECTS media-service: the per-app allow-list in fitmate-gitops
# (platform/netpol/dev/media-service.yaml) remains in force. trainee->media is BLOCKED while
# admin and trainer work. That layer never caused an outage.
#
# ROLLBACK: set namespaces = [] and apply. That destroys the 4 policies and returns staging
# to its pre-IN-50 state. The gitops allow-lists are a separate layer and are untouched by it.
inputs = {
  # The 4 fitmate namespaces that exist on staging. Verified against the live cluster:
  # exact match both ways — nothing on the cluster is missing from this list (which would
  # leave it unprotected), and nothing here is absent from the cluster (which would fail the
  # apply). Staging has FOUR services, not dev's ten; copying dev's list would be the exact
  # generalisation that caused both October outages.
  namespaces = [
    "fitmate-media-stg",
    "fitmate-trainee-stg",
    "fitmate-trainer-stg",
    "fitmate-website-stg",
  ]
}
