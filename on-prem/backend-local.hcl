# ─────────────────────────────────────────────────────────────────────────────
# LOCAL state backend — for stacks that deliberately do NOT include root.hcl (IN-12).
#
# WHY THIS FILE EXISTS
#   root.hcl generates the local backend for every stack that includes it. A few stacks
#   deliberately do not — the Cloudflare-only ones, which have no kube/Vault dependency and
#   avoid root.hcl so they do not pull in its providers and inputs. Those stacks therefore
#   received NO backend at all and kept writing state into .terragrunt-cache, which is exactly
#   the directory IN-12 exists to get state out of.
#
#   That was found the hard way: after `rm -rf .terragrunt-cache` across dev, the six Cloudflare
#   stacks planned "N to add" — Terraform could no longer see tunnels, DNS records and Access
#   apps that were very much still live. Applying that plan would have created DUPLICATES.
#
# HOW TO ENABLE — add alongside the stack's other includes:
#   include "backend_local" {
#     path = find_in_parent_folders("backend-local.hcl")
#   }
#
# ⚠️ MUTUALLY EXCLUSIVE with root.hcl and with backend.hcl (HCP). All three write backend.tf
# with if_exists = "overwrite_terragrunt", so including two means the last one silently wins.
# A stack includes EXACTLY ONE of:
#   • root.hcl          — the normal case
#   • backend-local.hcl — this file, for stacks that cannot include root.hcl
#   • backend.hcl       — HCP Terraform, opt-in, currently dormant (see IN-22)
#
# ⚠️ PATH MUST MATCH root.hcl EXACTLY, or a stack points at a state file that is not there and
# offers to rebuild live infrastructure. Note the deliberate use of get_terragrunt_dir() rather
# than path_relative_to_include(): the latter is resolved relative to the file doing the
# INCLUDING, so root.hcl (repo root) and this file (on-prem/) would produce paths differing by
# one segment — silently, and only for the stacks that use this file. Same expression as
# backend.hcl's workspace_name, for the same reason.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Keep in sync with root.hcl's `state_root`.
  state_root_local = get_env("TF_STATE_ROOT", "${get_env("HOME")}/.terragrunt-state/devops-terragrunt-environments")

  # Repo-relative path of the STACK (evaluated in the leaf context), independent of where this
  # partial lives in the tree.
  stack_rel_path = trimprefix(get_terragrunt_dir(), "${get_repo_root()}/")
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "local" {
    path = "${local.state_root_local}/${local.stack_rel_path}/terraform.tfstate"
  }
}
EOF
}
