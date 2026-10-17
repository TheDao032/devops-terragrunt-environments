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
# ─── IN-47 (2026-10-16): THE PRECONDITION ABOVE IS NOW MET ────────────────────────────
#
# The call graph was measured from FIVE sources, not one, because three of them are
# invisible to an obvious scan:
#
#   ConfigMaps      32 edges   (the obvious one)
#   Secrets          1 edge    admin -> media lives in admin-service-secrets, NOT a ConfigMap
#   Baked config     2 edges   media -> trainer:5001 is in config/<env>/config.yaml, in NO k8s object
#   ServiceMonitors  4 edges   prometheus scrape; a deny blanks dashboards with no error anywhere
#   HTTPRoutes       7 edges
#                   ─────────
#                   40 edges, 14 namespaces, every one receiving traffic
#
# trainer-dev alone has 11 inbound edges from 8 namespaces. The round-2 rollback happened
# because the allow-list covered media-dev, which has TWO inbound edges and no public route:
# the one namespace that could not reveal the bug.
#
# Allows are live in fitmate-gitops for all 14 namespaces (PRs #494, #495), and audited
# 14/14 with ZERO missing measured edges. That audit found a REAL defect: the hand-written
# media-dev list omitted website-dev, so every file upload on dev was already blocked
# before any baseline existed (fixed in #496, verified website -> media rc=0 after).
#
# 🔴 TRIALLED ON THE CLUSTER BEFORE THIS CHANGE, then removed. Three namespaces chosen to
# cover all four hazards, because media-dev covers none of them:
#
#   fitmate-media-dev           service-to-service only
#       admin/website/trainer -> media rc=0, trainee rc=4 (still denied), pod 1/1
#   fitmate-admin-website-dev   HAS a public HTTPRoute  <- the round-1 502 signature
#       admin-dev.fitmate.me 200, 200, 200 across three consecutive requests
#   fitmate-booking-dev         ServiceMonitor AND HTTPRoute  <- the full-risk case
#       prometheus targets up 32 -> 32, booking still scraped, admin -> booking rc=0
#
# All three trial policies were deleted afterwards (0 remain; the 14 allow-lists survive).
#
# Prometheus was queried via port-forward, NOT from inside its pod: that image is distroless
# and every in-pod query returned 0 bytes — which reads identically to "no targets".
#
# ⚠️ STILL NOT DONE HERE: stg. on-prem/fitmate/stg/netpol-baseline stays parked until the stg
# call graph is measured the same way. stg has only 4 services and its own topology; copying
# this list would be exactly the generalisation that caused both outages.
inputs = {
  namespaces = [
    "fitmate-admin-dev",
    "fitmate-admin-website-dev",
    "fitmate-booking-dev",
    "fitmate-inquiry-dev",
    "fitmate-media-dev",
    "fitmate-notification-dev",
    "fitmate-payment-dev",
    "fitmate-trainee-dev",
    "fitmate-trainer-dev",
    "fitmate-website-dev",
  ]
}
