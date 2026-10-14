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
inputs = {
  # Enumerated from `kubectl get ns | grep ^fitmate-` on 2026-10-14. My first draft
  # listed 7 from memory and MISSED THREE that exist: admin-website-dev,
  # notification-dev, website-dev. A baseline that silently skips a namespace is
  # worse than none, because the gap is invisible in the file that claims to close it.
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
