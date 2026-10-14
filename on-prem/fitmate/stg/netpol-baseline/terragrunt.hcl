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
# BEFORE THIS IS RE-ENABLED, the service-to-service call graph must be MEASURED — every
# caller of every service across all namespaces, including the website BFF, which calls them
# all — and an allow written for each edge. That is its own ticket, not a parameter change.
#
# WHAT STILL PROTECTS media-service: the per-app allow-list in fitmate-gitops
# (platform/netpol/dev/media-service.yaml) remains in force. trainee->media is BLOCKED while
# admin and trainer work. That layer never caused an outage.
#
# An EMPTY list is deliberate and must stay valid: applying it DESTROYS the 12 tracked
# policies, which is exactly what reconciles state with the rolled-back cluster. Leaving the
# old list here would make the next apply silently recreate the outage.
inputs = {
  namespaces = []
}
