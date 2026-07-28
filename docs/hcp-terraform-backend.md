# HCP Terraform (Terraform Cloud) remote backend — setup & usage

How to move an on-prem stack's Terraform state from **local** (inside `.terragrunt-cache`, where
`rm -rf` destroys it) to **HCP Terraform** (Terraform Cloud) for locking, sharing, and encrypted
remote state.

- **Provider:** HCP Terraform — `app.terraform.io`
- **Org:** `nthedao_org` (from `on-prem/backend.hcl` → `tf_organization`)
- **Backend definition:** `on-prem/backend-tfc.hcl` (opt-in, per stack)
- **One workspace per stack**, named after the stack's repo-relative path with `/`→`-`
  (e.g. `on-prem/fitmate/local/service-accounts` → **`on-prem-fitmate-local-service-accounts`**)
- **Execution mode: LOCAL** (mandatory — see Step 4)

> ⚠️ It is **opt-in**: a stack only uses HCP once *it* adds the `include "backend"`. Un-migrated
> stacks and CI keep working on local state until you migrate them deliberately.

---

## Prerequisites

- An HCP Terraform account, and the org **`nthedao_org`** must exist at `app.terraform.io`.
- `terragrunt`, and the Terraform/OpenTofu binary it drives, installed.
- For vault stacks: `VAULT_ADDR` / `VAULT_TOKEN` exported. For kube stacks: `direnv` loaded
  (provides `TG_KUBE_*`).

---

## Step 1 — Authenticate (`terraform login`)

Terragrunt has **no `login` command** — it reuses the Terraform/OpenTofu CLI credentials. Run the
login for whichever binary terragrunt drives:

```bash
terraform login            # writes ~/.terraform.d/credentials.tfrc.json
# or, if terragrunt drives OpenTofu:
tofu login
```

Follow the browser prompt → it creates an API token and saves it locally. Type `yes` to store it.

**Non-interactive / CI alternative** — skip `login` and export a token instead:

```bash
export TF_TOKEN_app_terraform_io=<user-or-team-API-token>
```

Verify:

```bash
terraform login   # if already logged in, it says credentials exist
# or check the file:
cat ~/.terraform.d/credentials.tfrc.json
```

---

## Step 2 — Opt the stack into the HCP backend

Add the `include "backend"` block to the stack's `terragrunt.hcl`, alongside the existing
`include "root"`:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "backend" {
  path = find_in_parent_folders("backend-tfc.hcl")
}
```

That's the only code change. `backend-tfc.hcl` generates a `backend.tf` with a `cloud {}` block
pointing at org `nthedao_org` and the per-stack workspace name.

---

## Step 3 — Initialize & migrate existing state

```bash
cd on-prem/fitmate/local/service-accounts     # the stack you just opted in
terragrunt run -- init -migrate-state
```

What happens:

- Terragrunt renders `backend.tf` (the `cloud {}` block) into the cache.
- `init` connects to HCP and **auto-creates the workspace** if it doesn't exist
  (e.g. `on-prem-fitmate-local-service-accounts`).
- `-migrate-state` detects the existing **local** state in the cache and offers to **copy it up**
  to HCP. Answer **`yes`**.

> If the stack has **no** prior state (fresh), a plain `terragrunt run -- init` is enough — no
> `-migrate-state` needed.

---

## Step 4 — ⚠️ Set the workspace to **Local** execution mode (mandatory)

HCP auto-creates workspaces in **Remote** execution mode, where HCP tries to run Terraform *itself*
— but it has **none** of terragrunt's generated files (providers, backend) or injected `inputs`, so
it fails. Terragrunt runs everything **on your machine**; HCP must only **store the state**.

After the first `init`:

1. HCP → **`nthedao_org`** → **Workspaces** → open the new workspace (e.g.
   `on-prem-fitmate-local-service-accounts`).
2. **Settings → General → Execution Mode → `Local`** → **Save settings**.

(Or pre-create the workspace as Local before the first `init`.)

Do this **once per workspace**.

---

## Step 5 — Verify

```bash
terragrunt run -- plan          # expect: 0 to add, 0 to change, 0 to destroy
```

A zero-diff plan confirms the state migrated intact and the backend is wired correctly. State now
lives in HCP (check the workspace's **States** tab).

---

## Everyday usage (unchanged)

```bash
terragrunt run -- plan
terragrunt run -- apply
terragrunt run -- apply -auto-approve      # non-interactive
terragrunt run -- state list               # any terraform subcommand works after `--`
terragrunt run -- import <addr> <id>
```

State locking is now automatic (HCP locks the workspace during a run).

---

## Roll out to more stacks

Repeat Steps 2–5 for each stack. Suggested order (deps first):

```
vault-auths → vault-secrets → service-accounts → external-secrets → k3s-resources → gitops-apps
```

Each gets its own workspace automatically (per-stack naming), so they never collide.

**Do NOT** uncomment the `generate "backend"` block in `root.hcl` to enable everything at once —
that would flip *all* on-prem tenants (incl. CI) to HCP simultaneously and require every stack's
state migrated in lockstep. The per-stack `include "backend"` keeps it incremental and safe.

---

## CI (Jenkins)

The pipeline runners need HCP credentials too:

- Add `TF_TOKEN_app_terraform_io` as a Jenkins credential and export it in the build env, **or**
  run `terraform login` on the runner.
- Migrate a tenant's CI stacks (`terragrunt run -- init -migrate-state`) only after the token is in
  place, so the first CI run after migration doesn't fail on auth.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Error: Required token could not be found` | Not logged in → `terraform login` or set `TF_TOKEN_app_terraform_io`. |
| Run tries to execute **in HCP** / can't find providers or inputs | Workspace is in **Remote** mode → set it to **Local** (Step 4). |
| `Error: Organization "nthedao_org" not found` | Create the org, or fix `tf_organization` in `on-prem/backend.hcl`. |
| `init` doesn't offer to migrate; state looks empty | The local cache state was already gone. Recover the resources with `terragrunt run -- import <addr> <id>` (namespaced id = `ns/name`, cluster-scoped = `name`). |
| Workspace name collision across stacks | Shouldn't happen — the name is the stack's repo-relative path. If it does, check `backend-tfc.hcl`'s `workspace_name` local. |
| Want to undo | Remove the `include "backend"` block and `terragrunt run -- init -migrate-state` to pull state back to local. |

---

## How it works (reference)

`on-prem/backend-tfc.hcl` generates this into each opted-in stack's cache as `backend.tf`:

```hcl
terraform {
  cloud {
    hostname     = "app.terraform.io"          # from backend.hcl → hostname
    organization = "nthedao_org"                # from backend.hcl → tf_organization
    workspaces {
      name = "on-prem-<tenant>-<env>-<stack>"   # replace(trimprefix(get_terragrunt_dir(), repo_root), "/", "-")
    }
  }
}
```

- `hostname` / `organization` come from `on-prem/backend.hcl` locals.
- `workspace_name` =
  `replace(trimprefix(get_terragrunt_dir(), "${get_repo_root()}/"), "/", "-")` → unique per stack.
- Because it's an `include` (not `read_terragrunt_config`), its `generate` block actually fires —
  see `~/obsidian-vaults/devops-architect-brain/30-references/terragrunt-include-vs-read-config.md`.

### Quick copy-paste (full flow for one stack)

```bash
# 0. auth (once per machine)
terraform login

# 1. add the include "backend" block to the stack's terragrunt.hcl (Step 2)

# 2. migrate state
cd on-prem/<tenant>/<env>/<stack>
terragrunt run -- init -migrate-state       # answer: yes

# 3. HCP UI: set the new workspace's Execution Mode = Local (Step 4)

# 4. verify
terragrunt run -- plan                      # expect 0 changes
```
