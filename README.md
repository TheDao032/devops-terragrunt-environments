# Terragrunt environments

Per-(location, tenant, env) Terragrunt wiring. Consumes generic modules
from sibling repo
[`devops-terraform-modules`](../devops-terraform-modules/).

## Repository layout

```
.
├── terragrunt.onprems.hcl       ← root template variant: kube/helm/vault providers
├── terragrunt.aws.hcl           ← root template variant: AWS provider + S3 backend
├── terragrunt.azure.hcl         ← root template variant: kube/helm/vault (cloud-as-platform)
├── terragrunt.gcp.hcl           ← root template variant: identical to azure
├── plm.Jenkinsfile              ← canonical on-prem CI: tenant + module choice; loadSecrets
├── k8s.Jenkinsfile              ← legacy variant
├── image.Jenkinsfile            ← runner Docker image
├── Dockerfile                   ← terraform + terragrunt + kubectl + helm runner
│
├── on-prem/
│   ├── location.hcl             ← `location = "on-prem"`
│   ├── bosch/                   ← per-tenant tree (see below)
│   └── renesas/                 ← per-tenant tree
│
├── aws/                         ← per-cloud env-tree (account/region/env)
├── azure/                       ← (mostly scaffolding)
├── gcp/                         ← (mostly scaffolding)
│
└── deployments/
    ├── on-prem/{build,deploy,destroy}.sh
    ├── on-prem/<tenant>/envs/<env>/*.bash[.example]
    ├── cloud/{build,deploy,destroy}.sh
    └── utils/{utils,envs,cloudflare}.sh
```

## Per-tenant on-prem layout

```
on-prem/<tenant>/
├── backend.hcl                  ← Terraform Cloud workspace + docker/github/ssh secrets
├── kube-config.hcl              ← KUBE_HOST + base64 client_key/cert/ca + KUBE_TOKEN (env-var indirection)
├── vault-config.hcl             ← VAULT_ADDR + VAULT_TOKEN (env-var indirection)
│
├── dev/
│   ├── env.hcl                  ← per-(tenant, env) — secret bundles for k3s/keycloak/db/agile/…
│   ├── gitops-apps/             ← gitops Apps managed by ArgoCD
│   ├── cert-manager/            ← self-contained chart submodule (helm/charts/cert-manager)
│   ├── external-secrets/        ← namespaced ESO + Vault token
│   ├── k3s-resources/           ← cluster-bootstrap addons (helm meta-module ×6+)
│   ├── kafka-ui/                ← self-contained chart submodule
│   ├── keycloak/                ← self-contained chart submodule
│   ├── loki/                    ← self-contained chart submodule
│   ├── prometheus/              ← self-contained chart submodule
│   ├── service-accounts/        ← k8s SAs + RBAC
│   ├── vault-roles/             ← Vault AppRole + policies
│   └── vault-secrets/           ← Vault KV-v2 mount + secrets seeding
│
└── local/                       ← engineer laptop k3d (minimal subset)
    ├── env.hcl
    ├── gitops-apps/   external-secrets/   k3s-resources/   vault-roles/   vault-secrets/
```

**Tenant lives only in this repo.** Each tenant calls the same generic
module from `devops-terraform-modules` with different inputs.

## Module-source conventions

Every leaf points at the canonical generic module:

```hcl
# Bootstrap addons (k3s-resources leaf — calls helm meta-module 6×+ internally)
source = "../../../../../devops-terraform-modules//on-prem/k3s-resources"

# Self-contained chart submodule (cert-manager, kafka-ui, keycloak, loki, prometheus)
source = "../../../../../devops-terraform-modules//on-prem/helm/charts/<chart>"

# Non-helm generic modules
source = "../../../../../devops-terraform-modules//on-prem/<module>"
# ↑ gitops-apps, external-secrets, service-accounts, vault-roles, vault-secrets
```

The `5 ../`s assume sibling repos under the same parent dir
(`Infrastrutures/devops-terragrunt-environments` and
`Infrastrutures/devops-terraform-modules`).

## Wrapper script contract

```bash
./deployments/on-prem/build.sh   <tenant> <env> [module]
./deployments/on-prem/deploy.sh  <tenant> <env> [module]
./deployments/on-prem/destroy.sh <tenant> <env> [module]
```

Examples:
```bash
./deployments/on-prem/build.sh bosch local
./deployments/on-prem/deploy.sh renesas dev k3s-resources
./deployments/on-prem/destroy.sh bosch dev
```

The wrappers:
1. Source `deployments/utils/{utils,envs}.sh` (logging helpers + baseline env vars).
2. Source every `*.bash` under `deployments/on-prem/<tenant>/envs/<env>/`
   — these run `vault login` and export `KUBE_*` from Vault.
3. `cd on-prem/<tenant>/<env>[/module]` and run terragrunt.

## Authentication

```bash
export VAULT_ADDR=https://vault.<tenant>.example.com
export VAULT_TOKEN=hvs.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Then the wrapper's `deploy-env.bash` reads kube creds from Vault path
`<env>/k3s/creds` and exports them as `KUBE_*` env vars; the root
terragrunt template generates `kubernetes`, `helm`, `kubectl`, `vault`
providers from those.

## CI

`plm.Jenkinsfile`:
- **Parameters:** `tenant` (`bosch`/`renesas`), `terraform_module` (specific module or empty for `run-all`).
- **Branch → ENVIRONMENT:** `env.GIT_BRANCH` is consumed as the env name.
- **`loadSecrets`:** wraps stages with Jenkins file credentials
  (`k3s-env`, `agile-app-env`, `agile-db-env`, `hikari-conn-env`,
  `ldap-env`, `pod-restart-collector-env`, `query-env`, `vault-env`).

A pipeline run on the `dev` branch with `tenant=bosch, terraform_module=k3s-resources`
is equivalent to:
```bash
./deployments/on-prem/build.sh  bosch dev k3s-resources
./deployments/on-prem/deploy.sh bosch dev k3s-resources
```

## Adding a new tenant

```bash
TENANT=customer-x

# 1. Per-tenant config (copy from existing)
mkdir -p on-prem/${TENANT}/{dev,local}
cp on-prem/bosch/{backend,kube-config,vault-config}.hcl on-prem/${TENANT}/

# 2. Mirror env trees from the closest tenant
cp -R on-prem/bosch/dev/   on-prem/${TENANT}/dev/
cp -R on-prem/bosch/local/ on-prem/${TENANT}/local/
# Edit env.hcl for tenant-specific secret paths, then per-leaf inputs.

# 3. Per-tenant runtime env-vars
mkdir -p deployments/on-prem/${TENANT}/envs/{dev,local,stg,prod}
cp deployments/on-prem/bosch/envs/*/deploy-env.bash.example deployments/on-prem/${TENANT}/envs/.../

# 4. Add ${TENANT} to plm.Jenkinsfile's `tenant` parameter choices.
# 5. Generate the per-tenant ansible-vault password file at
#    ~/.config/ansible-vault/${TENANT} (filesystem-only, not in repo).
```

## Adding a new environment

```bash
TENANT=bosch
NEW_ENV=stg

cp -R on-prem/${TENANT}/dev   on-prem/${TENANT}/${NEW_ENV}
# Edit on-prem/${TENANT}/${NEW_ENV}/env.hcl  (set environment = "stg")

mkdir -p deployments/on-prem/${TENANT}/envs/${NEW_ENV}
cp deployments/on-prem/${TENANT}/envs/dev/deploy-env.bash.example \
   deployments/on-prem/${TENANT}/envs/${NEW_ENV}/deploy-env.bash.example
```

## Cloud env trees

Shape: `<cloud>/<account-or-region>/<region>/<env>/<resource>/terragrunt.hcl`.
Today these are 0-byte stubs reserved for future work; cloud account or
subscription is itself the tenant boundary.

## Operational gotchas

### ⚠️ Never export bare `KUBE_*` env vars for local runs — use `TG_KUBE_*`

The `hashicorp/kubernetes` (and `helm`, `kubectl`) providers **natively read** a fixed set of
env vars as their own config: `KUBE_HOST`, `KUBE_CLIENT_CERT_DATA`, `KUBE_CLIENT_KEY_DATA`,
`KUBE_CLUSTER_CA_CERT_DATA`, `KUBE_CONFIG_PATH`, `KUBE_CTX`, `KUBE_TOKEN`
([provider docs](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)).
They expect **raw PEM**. Our kubeconfig `*-data` fields are **base64**, and `root.hcl` /
`terragrunt.onprems.hcl` generate `provider-kube.tf` with `base64decode(...)`.

If you export the base64 into the bare `KUBE_*` names, the provider **reads the base64 directly
and overrides the inline `base64decode(...)`** → `'client_certificate' is not a valid PEM encoded
certificate`. This only bites stacks that actually create `kubernetes_*` resources (e.g.
`service-accounts`) — `helm`/`kubectl`-only stacks (`k3s-resources`) and `vault`-only stacks
(`vault-auth`, `vault-secrets`) never configure the kubernetes provider, so they silently work.

- **Local dev** → the repo `.envrc` exports **`TG_KUBE_*`** (prefix hides them from the provider);
  `on-prem/fitmate/kube-config.hcl` reads `get_env("TG_KUBE_*")`. Use `kubectl config view --minify`
  so `clusters[0]`/`users[0]` resolve the **current context**, not entry-0 of a merged kubeconfig.
- **CI (Jenkins, bosch/renesas/aws)** → keeps bare `KUBE_*` because Jenkins injects **raw PEM** from
  Vault (matches what the provider wants), so those tenants' `kube-config.hcl` still read `KUBE_*`.

### ⚠️ Terraform state lives *inside* `.terragrunt-cache` (no remote backend)

The `generate "backend"` block in `root.hcl` is commented out, so each stack uses **local** state
stored in its `.terragrunt-cache/…/terraform.tfstate`. **`rm -rf .terragrunt-cache` deletes the
state** and orphans live cluster resources → next apply fails with `… already exists`. Recover by
importing the orphans back into state, e.g.:

```bash
terragrunt run -- import 'kubernetes_service_account.sa["traefik"]' kube-system/traefik
terragrunt run -- import 'kubernetes_cluster_role.manager["traefik"]' traefik-manager
```

Consider wiring a real remote backend so cache clears are safe.

## See also

- [`devops-terraform-modules/`](../devops-terraform-modules/) — the modules consumed here.
- `devops-tools/` — Ansible inventories, Vagrant scenarios, Packer image baking.
