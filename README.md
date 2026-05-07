# Terragrunt environments

Infrastructure-as-code orchestration with Terragrunt + Terraform across
multiple **locations**, **tenants**, and **environments**.

## Repository layout

```
<LOCATION>/<TENANT>/<ENVIRONMENT>/<RESOURCE>/terragrunt.hcl    ← on-prem (per-tenant)
<CLOUD>/<ACCOUNT-OR-REGION>/<ENVIRONMENT>/<RESOURCE>/...        ← public clouds
deployments/<LOCATION>/{build,deploy,destroy}.sh                ← orchestration wrappers
deployments/<LOCATION>/<TENANT>/envs/<ENVIRONMENT>/*.bash       ← runtime env-vars per (tenant, env)
```

The on-prem path is **tenant-segmented** because each tenant (bosch, renesas)
runs on its own k3s cluster, has its own Vault, its own Terraform Cloud
workspace, and its own deploy-time secrets. The cloud paths are **not**
tenant-segmented because the cloud account is itself the tenant boundary.

### On-prem layout in detail

```
on-prem/
├── location.hcl                    ← shared across tenants ("on-prem")
├── bosch/
│   ├── backend.hcl                 ← per-tenant Terraform Cloud workspace
│   ├── kube-config.hcl             ← per-tenant kube creds (env-var indirection)
│   ├── vault-config.hcl            ← per-tenant Vault address + token
│   ├── dev/
│   │   ├── env.hcl
│   │   └── {consul, jenkins, kafka, prometheus, vault, vault-secrets}/terragrunt.hcl
│   └── local/
│       ├── env.hcl
│       └── {cert-manager, consul, jenkins, kafka, prometheus, service-accounts, vault, vault-secrets}/terragrunt.hcl
└── renesas/
    ├── backend.hcl
    ├── kube-config.hcl
    ├── vault-config.hcl
    ├── dev/   …
    └── local/ …
```

Each tenant's `terragrunt.hcl` files reference the matching tenant subtree
in the modules sibling repo:

```hcl
# on-prem/bosch/dev/jenkins/terragrunt.hcl
terraform {
  source = "../../../../../devops-terraform-modules//on-prem/bosch/jenkins"
}
```

## Cloud layout

| Cloud | Path shape |
|---|---|
| AWS   | `aws/<account>/<region>/<environment>/<resource>/terragrunt.hcl` |
| Azure | `azure/<region>/<environment>/<resource>/terragrunt.hcl` |
| GCP   | `gcp/<region>/<environment>/<resource>/terragrunt.hcl` |

Cloud accounts/subscriptions are themselves the tenant boundary — adding a
tenant means adding a new account or subscription, not subdividing within.

## Apply / Destroy

### Authentication

#### On-prem (k3s + Vault)
The wrapper scripts source `deployments/on-prem/<tenant>/envs/<env>/deploy-env.bash`
which reads cluster credentials from Vault using a session token you provide:

```bash
export VAULT_ADDR=https://vault.<tenant>.example.com
export VAULT_TOKEN=hvs.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### Azure
See [Terraform AzureRM Authentication](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure).
Local: `az login`. CI: Managed Service Identity or OpenID Connect.

#### AWS / GCP
Provider-side credentials via env vars or workload identity.

### Execution — on-prem

**New CLI shape (tenant-aware):**

```bash
# Plan
./deployments/on-prem/build.sh   <tenant> <environment> [module]

# Apply
./deployments/on-prem/deploy.sh  <tenant> <environment> [module]

# Tear down
./deployments/on-prem/destroy.sh <tenant> <environment> [module]
```

Examples:

```bash
# Plan everything for bosch local
./deployments/on-prem/build.sh bosch local

# Apply only jenkins for renesas dev
./deployments/on-prem/deploy.sh renesas dev jenkins

# Destroy everything for bosch dev
./deployments/on-prem/destroy.sh bosch dev
```

The wrappers `cd` into `on-prem/<tenant>/<environment>` and either run the
single requested module or `terragrunt run-all` across the directory.

### Execution — manual / no wrapper

```bash
cd on-prem/bosch/local
rm -rf **/.terragrunt-cache* **/.terraform.lock.hcl
terragrunt run-all init
terragrunt run-all apply
```

## Adding a new tenant

1. Create `on-prem/<tenant>/{backend,kube-config,vault-config}.hcl` with
   tenant-specific values (TFC workspace, vault addr, kube creds).
2. Copy `on-prem/<existing-tenant>/<env>` → `on-prem/<tenant>/<env>` and
   adjust `env.hcl` + per-resource `terragrunt.hcl` source paths to point at
   `devops-terraform-modules//on-prem/<tenant>/<resource>`.
3. Create `deployments/on-prem/<tenant>/envs/<env>/deploy-env.bash` with
   tenant-specific runtime vars (k3s ip ranges, secrets paths, registry).
4. Mirror the new tenant subtree in
   [`devops-terraform-modules`](../devops-terraform-modules/) under
   `on-prem/<tenant>/<resource>`.
5. Add the tenant to the `tenant` parameter choices in `Jenkinsfile`
   and `plm.Jenkinsfile`.

## Adding a new environment to an existing tenant

```bash
TENANT=bosch
NEW_ENV=staging

cp -R on-prem/${TENANT}/dev    on-prem/${TENANT}/${NEW_ENV}
# edit on-prem/${TENANT}/${NEW_ENV}/env.hcl  (set environment = "staging")

mkdir -p deployments/on-prem/${TENANT}/envs/${NEW_ENV}
cp deployments/on-prem/${TENANT}/envs/dev/deploy-env.bash \
   deployments/on-prem/${TENANT}/envs/${NEW_ENV}/deploy-env.bash
# edit the new deploy-env.bash for staging-specific vars
```

## CI

Jenkinsfiles (`Jenkinsfile`, `plm.Jenkinsfile`) declare two parameters:

- `tenant` — choice between `bosch` and `renesas`.
- `terraform_module` — single module name, or empty for `run-all`.

Branch name is consumed as `ENVIRONMENT`. So a pipeline run on the `dev`
branch with `tenant=bosch, terraform_module=jenkins` is equivalent to:

```bash
./deployments/on-prem/build.sh bosch dev jenkins
./deployments/on-prem/deploy.sh bosch dev jenkins
```
