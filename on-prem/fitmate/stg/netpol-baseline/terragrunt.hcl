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
  # ⚠️ stg has only TWO fitmate namespaces today (measured): trainee and website.
  # media and trainer do not exist on stg, so IN-40's media rule has no stg
  # counterpart until IN-35 onboards them. Listing them here would fail the apply.
  namespaces = [
    "fitmate-trainee-stg",
    "fitmate-website-stg",
  ]
}
