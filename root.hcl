# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform that provides extra tools for working with multiple Terraform modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Providers are split into per-provider partials (on-prem/{kube,vault,postgresql,keycloak}.hcl);
  # each stack includes only the ones it needs. This root no longer generates the kube provider, so
  # the kube connection locals moved out (they live in kube.hcl now).
  backend_vars      = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  backend_hostname  = local.backend_vars.locals.hostname
  backend_org       = local.backend_vars.locals.tf_organization
  backend_workspace = local.backend_vars.locals.tf_workspaces_name

  # Automatically load region-level variables
  location_vars = read_terragrunt_config(find_in_parent_folders("location.hcl"))
  location      = local.location_vars.locals.location

  # Automatically load environment-level variables
  organizaiton_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  organizaiton      = local.organizaiton_vars.locals.infras_organization

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  # ── Terraform state location (IN-12) ────────────────────────────────────────────────────────────
  # State lives OUTSIDE the repository and outside .terragrunt-cache.
  #
  # It used to land in .terragrunt-cache/<hash>/.../terraform.tfstate — a directory that terragrunt
  # regenerates, that tooling cleans, and that every guide says is safe to delete. It is not:
  # deleting one does not lose the resources, it ORPHANS them. Vault policies, Keycloak realms and
  # clients, Postgres databases, and Cloudflare tunnels/DNS/Access apps that live outside the
  # cluster entirely. The next apply then tries to CREATE them again, which for a Cloudflare tunnel
  # or a Keycloak client is a duplicate or a hard failure, not a no-op. Recovery is a hand-written
  # `import` per resource. This has already happened once in this project.
  #
  # Outside the REPO, not merely outside the cache, because this workspace has already been
  # relocated by cloning fresh from origin — which would have silently taken in-repo state with it.
  # .gitignore does protect against committing it, but not against a re-clone.
  #
  # Override with TF_STATE_ROOT (e.g. to point several checkouts at one state tree).
  state_root = get_env("TF_STATE_ROOT", "${get_env("HOME")}/.terragrunt-state/devops-terragrunt-environments")
}

# required_version ONLY. Provider requirements + configs are split into per-provider partials that
# each stack includes as needed (Terraform merges required_providers across terraform{} blocks):
#   on-prem/kube.hcl (kubernetes+helm+kubectl) · vault.hcl · postgresql.hcl · keycloak.hcl
# Every on-prem stack (fitmate + bosch + renesas) now initializes ONLY the providers it includes.
# aws stacks declare the aws provider within their own tree.
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.11.2, < 2.0.0"
}
EOF
}

# Generate the backend. One state file per unit, keyed by its path relative to this root, so the
# layout on disk mirrors the layout in the repo and a unit's state is findable by eye.
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "local" {
    path = "${local.state_root}/${path_relative_to_include()}/terraform.tfstate"
  }
}
EOF
}

# Generate Backend
# generate "backend" {
#   path      = "backend.tf"
#   if_exists = "overwrite_terragrunt"
#   contents  = <<EOF
#     terraform {
#       cloud {
#         hostname = "${local.backend_hostname}"
#         organization = "${local.backend_org}"
#         workspaces {
#           name = "${local.backend_workspace}"
#         }
#       }
#     }
# EOF
# }

# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL PARAMETERS
# These variables apply to all configurations in this subfolder. These are automatically merged into the child
# `terragrunt.hcl` config via the include block.
# ---------------------------------------------------------------------------------------------------------------------

# Configure root level variables that all resources can inherit. This is especially helpful with multi-account configs
# where terraform_remote_state data sources are placed directly into the modules.
inputs = merge(
  local.environment_vars.locals,
  local.backend_vars.locals, # includes the kube provider config now
  local.location_vars.locals,
)
