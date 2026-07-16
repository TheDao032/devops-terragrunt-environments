# ─────────────────────────────────────────────────────────────────────────────
# HCP Terraform (Terraform Cloud) remote-state backend — OPT-IN, PER STACK.
#
# WHY: on-prem stacks default to LOCAL state stored inside .terragrunt-cache (root.hcl's
# `generate "backend"` is commented out), so `rm -rf .terragrunt-cache` destroys state and
# orphans real resources. This moves a stack's state to HCP Terraform (locking + sharing +
# encryption). It is opt-in so it never breaks un-migrated stacks or CI.
#
# HOW TO ENABLE for a stack — add this include ALONGSIDE the root include in its terragrunt.hcl:
#   include "backend" {
#     path = find_in_parent_folders("backend-tfc.hcl")
#   }
#
# ONE WORKSPACE PER STACK: the workspace name is the stack's repo-relative path with "/"→"-"
# (e.g. on-prem-fitmate-local-service-accounts), so stacks never collide on one workspace.
# org/hostname come from on-prem/backend.hcl.
#
# PREREQUISITES (one-time, on your machine / in CI):
#   1. Auth:  terraform login          (writes ~/.terraform.d/credentials.tfrc.json)
#             — or export TF_TOKEN_app_terraform_io=<user/team token>
#   2. The org "nthedao_org" must exist at app.terraform.io.
#   3. ⚠️ EXECUTION MODE = LOCAL. Terragrunt generates providers + injects inputs on THIS
#      machine, so the workspace must run locally (HCP only stores state). Auto-created
#      workspaces default to "Remote" — after the first init, set it to Local in
#      HCP → Workspace → Settings → General → Execution Mode. (Or pre-create it as Local.)
#
# FIRST-TIME STATE MIGRATION (copies the existing local cache state into HCP):
#   terragrunt run -- init -migrate-state      # answer "yes" to copy state
# Verify afterwards:  terragrunt run -- plan   → expect 0 changes.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  backend_vars = read_terragrunt_config(find_in_parent_folders("backend.hcl"))

  # Stack's path relative to the repo root, "/"→"-", as the unique HCP workspace name.
  # Evaluated in the CHILD (leaf) context, so get_terragrunt_dir() is the stack's own dir.
  workspace_name = replace(trimprefix(get_terragrunt_dir(), "${get_repo_root()}/"), "/", "-")
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  cloud {
    hostname     = "${local.backend_vars.locals.hostname}"
    organization = "${local.backend_vars.locals.tf_organization}"
    workspaces {
      name = "${local.workspace_name}"
    }
  }
}
EOF
}
