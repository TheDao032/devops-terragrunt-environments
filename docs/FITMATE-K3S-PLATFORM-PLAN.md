# FITMate — k3s Platform Resource Plan & Chart Upgrade Review

_Compiled 2026-07-03. Versions verified via ArtifactHub / GitHub releases / project index.yaml. Re-run `helm repo update && helm search repo <chart>` before executing — patch releases move fast._

Scope: on-prem k3s for the FITMate payment/marketplace platform. Your cluster keeps **bundled Traefik + servicelb**, disables **CoreDNS** (deployed via helm). Secrets = **HashiCorp Vault + External Secrets Operator (ESO)**.

---

## 0. TL;DR — the 5 things that matter most

1. **Bitnami is a dead end.** Your `keycloak` (Bitnami 24.2.0) and `kafka` (Bitnami 31.0.0) charts are **frozen & unpatched** — Broadcom moved free Bitnami images to `docker.io/bitnamilegacy` (archived, no CVE patches) in Sept 2025; default image refs stop resolving. **Migrate both.**
2. **Your real auth (SuperTokens) is missing from k3s; the auth you deploy (Keycloak) is barely used.** SuperTokens = 294 files in the app, deployed only in docker-compose today. Keycloak's only consumer is **kafka-ui**. → Add SuperTokens Core; drop or repurpose Keycloak.
3. **Three upgrades are "stepwise or you break the cluster":** external-secrets (0.15→2.7, API `v1beta1→v1`), kube-prometheus-stack (65→87, per-major CRDs), argo-cd (7.8→10.1, CRD adoption + Argo v2→v3).
4. **CoreDNS chart is from 2021** (`1.10.101-build2021022303`, RKE2 fork) → replace with official `coredns/helm` 1.46.0 (fresh values).
5. **New payment-grade adds:** CloudNativePG (HA Postgres), Velero (backups), Redis (Opstree), Tempo+OTel (tracing), KEDA (Kafka-lag autoscaling), MetalLB (stable ingress VIP for webhooks).

---

## 1. How your config is structured (what "adjust config" means)

Each chart = a **generic module** `devops-terraform-modules//on-prem/helm/charts/<name>` (a `helm_release` driven by `var.chart_version`, `var.helm_repository`, `var.helm_release_chart`, + values), and the **actual pins live in terragrunt inputs** per env, e.g. `on-prem/fitmate/prod/<name>/terragrunt.hcl`:

```hcl
chart_version      = "1.16.1"
helm_repository    = "https://charts.jetstack.io"
helm_release_chart = "cert-manager"
```

So:
- **Upgrade** = bump `chart_version` (+ maybe `helm_repository`) in the terragrunt input, reconcile values, `terragrunt apply`.
- **Add** = new `helm/charts/<name>` module + new `fitmate/<env>/<name>/` terragrunt unit.

---

## 2. Bill of materials — existing charts (REVIEW: your version → latest)

| Component | Your chart / ver | Latest (Jul 2026) | Repo | Risk | Action |
|---|---|---|---|---|---|
| **cert-manager** | cert-manager `1.16.1` | **1.20.3** | `oci://quay.io/jetstack/charts/cert-manager` (or `charts.jetstack.io`) | Med | Stepwise 1.16→…→1.20, `kubectl apply` CRDs each hop. **Avoid 1.19.0** (re-issuance bug). v1.17 changed RSA sig algs; ACME metric `path` label removed → fix dashboards. |
| **external-secrets (ESO)** | external-secrets `0.15.0` | **2.7.0** | `https://charts.external-secrets.io` | 🔴 High | **Stepwise 0.15→0.16→0.17** — v0.17 drops the `v1beta1` API; migrate all `ExternalSecret`/`ClusterSecretStore` → `v1` first. v1.0.0 (Nov 2025) = GA, chart then tracks app 1:1 into 2.x. |
| **kube-prometheus-stack** | `65.1.0` (Prom+Grafana+Alertmgr) | **87.5.1** | `https://prometheus-community.github.io/helm-charts` | 🔴 High | 22 major bumps — read UPGRADE.md **per hop**; `kubectl apply --server-side` the Prometheus-Operator CRDs each major (or `crds.upgradeJob.enabled=true`, ≥68.4.0). Grafana subchart now sources from **`grafana-community`** repo. |
| **loki** | (unit deploys `alloy 0.10.0`) | loki **18.3.1** | ⚠️ repo **moved** → `https://grafana-community.github.io/helm-charts` | Med | OSS Loki chart left `grafana/loki` (last 6.55.0) for `grafana-community/loki` (Mar 2026, now 18.x). GEL support dropped in community 8.0.0. Update repo URL. |
| **grafana-alloy** | alloy `0.10.0` | **1.10.0** | `https://grafana.github.io/helm-charts` | Med | Chart crossed 1.0.0; review 0.x→1.0 values/templating + Alloy config-syntax deprecations. |
| **argo-cd** | argo-cd `7.8.10` | **10.1.1** (app v3.4.4) | `https://argoproj.github.io/argo-helm` | 🔴 High | Stepwise 7→8→9→10. **8.0** moves CRDs into templates → adopt existing CRDs (Helm meta labels) or upgrade fails; redis-ha immutable-selector break (disable→upgrade→re-enable); Argo **v2→v3** boundary. |
| **argocd-image-updater** | `0.12.0` | **1.2.4** (app v0.16.0) | `https://argoproj.github.io/argo-helm` | Med | 1.0.0 changes recommended namespace to same as Argo CD. |
| **reloader** | reloader `2.0.0` | **2.2.14** | `https://stakater.github.io/stakater-charts` | 🟢 Low | Same major — safe patch/minor bump. |
| **jenkins** | jenkins `5.8.32` | **5.9.32** (Jenkins 2.555.x) | `https://charts.jenkins.io` | Med | Chart minor, but appVersion needs **Java 21+** (Java 17 removed). Verify plugin compat. |
| **coredns** | `1.10.101-build2021022303` (rke2 fork) | **1.46.0** (app 1.13.1) | `https://coredns.github.io/helm` | Med | 2021 fork — treat as **fresh values install**, not in-place. Different `servers` block + autoscaler. |
| **kafka** | **Bitnami** kafka `31.0.0` | Bitnami **32.4.3 (FROZEN)** | — | 🔴 Migrate | → **Strimzi operator 1.1.0** (`oci://quay.io/strimzi-helm/strimzi-kafka-operator` / `strimzi.io/charts`), supports Kafka 4.x. CNCF-standard. |
| **kafka-ui** | appscode kafka-ui `2024.6.4` | kafbat **1.6.4** | `oci://ghcr.io/kafbat/helm-charts` (`ui.charts.kafbat.io`) | Med | provectus chart archived → **kafbat/kafka-ui**. |
| **keycloak** | **Bitnami** keycloak `24.2.0` | Bitnami **25.2.0 (FROZEN)** | — | 🔴 Migrate/Drop | Only consumer = kafka-ui. **Drop** (secure kafka-ui via Traefik ForwardAuth) OR make it real ops-SSO via official **Keycloak Operator** (`quay.io/keycloak/keycloak-operator`). |
| **vault** | vault `0.28.1` | **0.33.0** | `https://helm.releases.hashicorp.com` | Low-Med | Version bump; Vault 2.x under BUSL — note license / OpenBao if relevant. |
| **consul** | consul `1.5.3` | **2.0.1** | `https://helm.releases.hashicorp.com` | Med | Major 1.5→2.0 breaking (only if actually used). Chart now in `hashicorp/consul-k8s`. |
| **nginx-gateway-fabric** | `1.6.2` | **2.6.6** | `oci://ghcr.io/nginx/charts` | Med | Major 1→2 (Gateway API changes). Only if used. |
| **kong** | (module available) | ingress **0.24.0** / kong **3.4.1** | `https://charts.konghq.com` | — | Use `kong/ingress` for new installs. Only if you need it over Traefik. |

---

## 3. Bill of materials — NEW charts to ADD (payment-grade)

| Component | Chart (repo / name) | Latest | Docs | Vault/ESO wiring |
|---|---|---|---|---|
| **CloudNativePG** (operator) | `https://cloudnative-pg.github.io/charts` / `cloudnative-pg` | **0.29.0** | cloudnative-pg.io/documentation | Operator holds no app secrets. |
| **CloudNativePG** (cluster) | same repo / `cluster` | **0.7.0** | ↑ | DB creds via `superuserSecret`/bootstrap secret; backup S3 creds via `barmanObjectStore.s3Credentials.*` `secretKeyRef` → **ESO populates**. Use the **Barman Cloud Plugin** (inline barman deprecated in 1.26). |
| **Velero** (backup) | `https://vmware-tanzu.github.io/helm-charts` / `velero` | **12.1.0** (app 1.18.1) | velero.io/docs | `credentials.existingSecret` — key **must be `cloud`** = INI AWS creds. ESO must **template** the INI blob into `cloud`. |
| **Redis** (HA) | `https://ot-container-kit.github.io/helm-charts` / `redis-operator` + `redis-sentinel` | operator **0.25.0**, sentinel **0.16.13** | ot-container-kit.github.io/redis-operator | Password via CRD `kubernetesConfig.redisSecret {name,key}` → **ESO populates**. Non-Bitnami, maintained. |
| **KEDA** (autoscale) | `https://kedacore.github.io/charts` / `keda` | **2.20.1** | keda.sh/docs | Kafka scaler: trigger `type: kafka` (`bootstrapServers`, `consumerGroup`, `topic`, `lagThreshold`). Manages HPA under the hood. |
| **MetalLB** (LB VIP) | `https://metallb.github.io/metallb` / `metallb` | **0.16.1** | metallb.io | Post-install CRs: `IPAddressPool` + `L2Advertisement` (L2 mode). Pick IPs outside DHCP. Gives Traefik a stable failover VIP for payment webhooks. |
| **Grafana Tempo** (tracing) | `https://grafana.github.io/helm-charts` / `tempo` | **1.24.4** | grafana.com/docs/tempo | Start single-binary `tempo`; point OTel Collector OTLP exporter at it. (`tempo-distributed` 1.61.3 only if scaling out.) |
| **OTel Collector** | `https://open-telemetry.github.io/opentelemetry-helm-charts` / `opentelemetry-collector` | **0.162.0** (app 0.154.0) | opentelemetry.io/docs/collector | Plain collector; you supply pipeline (OTLP receiver → Tempo exporter). Operator (0.118.0) only if you want auto-instrumentation CRDs (needs cert-manager). |
| **SuperTokens Core** (auth) | ⚠️ **no official Helm chart** | image `registry.supertokens.io/supertokens/supertokens-postgresql` | supertokens.com/docs/deployment/self-host-supertokens | Deploy as plain Deployment+Service; backend = a **CNPG Postgres** cluster. Conn URI/password via **ESO env** (`POSTGRESQL_CONNECTION_URI`). |
| **metrics-server** | (bundled by k3s) | 3.13.1 chart exists | — | **Do NOT install** — k3s ships it. Verify `kubectl top nodes`. KEDA/HPA depend on it. |
| **MinIO** (S3 target) | ⚠️ **archived 2026** | operator 7.1.1 (archived) | — | MinIO Community + operator archived; company steers to commercial AIStor. **Reconsider** — evaluate **SeaweedFS / Garage / Rook-Ceph RGW** for the on-prem S3 backup target instead. |

---

## 4. Critical migrations (do these first — they're not optional upgrades)

1. **Kafka: Bitnami → Strimzi** — Bitnami kafka is frozen/unpatched. Strimzi 1.1.0 is the CNCF standard (operator + Topic/User CRDs). New module `helm/charts/strimzi`.
2. **Keycloak: decide + act** — it gates only kafka-ui. Recommended: **remove Keycloak**, protect kafka-ui with a **Traefik ForwardAuth/BasicAuth + IP-allowlist** middleware. (Keep only if you commit to Keycloak as SSO for ArgoCD+Grafana+Jenkins+kafka-ui.)
3. **SuperTokens: add to k3s** — it's the app's actual auth, currently docker-compose only. Deploy image + CNPG backend. Without it, login breaks on k3s.
4. **kafka-ui: appscode/provectus → kafbat** (1.6.4).
5. **CoreDNS: rke2-2021 fork → coredns/helm 1.46.0** (fresh values).
6. **MinIO: reconsider** the archived project before making it your backup target.

---

## 5. Concrete directory structure to add a new chart

Example — **CloudNativePG** (operator + a fitmate DB cluster):

```
devops-terraform-modules/on-prem/helm/charts/cloudnative-pg/     # NEW generic module
├── main.tf          # helm_release (var.chart_version / repo / chart) + optional Cluster CR
├── variables.tf     # chart_version, helm_repository, helm_release_chart, namespace, values
├── outputs.tf
└── templates/       # Cluster CR, backup ObjectStore, ESO ExternalSecret templates

devops-terragrunt-environments/on-prem/fitmate/
├── local/cloudnative-pg/terragrunt.hcl    # pins: chart_version="0.29.0", repo=cnpg charts
└── prod/cloudnative-pg/terragrunt.hcl
```

Then wire it into the deploy order (dependency blocks: DB cluster `depends_on` operator; SuperTokens `depends_on` its CNPG cluster). SuperTokens has no chart → a small `helm/charts/supertokens` module wrapping a Deployment/Service (or a raw `kubernetes_*` module), same pattern.

---

## 6. Secrets pattern (Vault → ESO → chart)

Every chart above that needs a secret should consume a **K8s Secret that ESO syncs from Vault** (never inline). Standard shape:

```
Vault KV (fitmate/<env>/<app>)  →  ClusterSecretStore/SecretStore (Vault)
   →  ExternalSecret (app namespace)  →  K8s Secret  →  chart `existingSecret`/`secretKeyRef`
```

Per-chart key: CNPG `s3Credentials.*.secretKeyRef`; Velero `existingSecret` (key `cloud`, ESO **template** the INI); Redis `redisSecret{name,key}`; SuperTokens env `secretKeyRef`; cert-manager Cloudflare token `secretKeyRef`. **Note: ESO chart itself needs the `v1` API migration (§2) before you lean on it harder.**

---

## 7. Suggested rollout order

1. **Foundation fixes:** CoreDNS (official chart), ESO stepwise 0.15→0.17 (API migration), metrics-server (confirm bundled).
2. **Data + auth:** CloudNativePG → SuperTokens (on CNPG) → Redis. Retire/repoint Keycloak.
3. **Messaging:** Kafka Bitnami → Strimzi; kafka-ui → kafbat.
4. **DR:** pick S3 target (not MinIO?) → Velero + CNPG Barman backups.
5. **Observability:** Tempo + OTel Collector; then kube-prometheus-stack stepwise 65→87; Loki repo move; alloy 0.x→1.x.
6. **Networking/scale:** MetalLB (prod VIP) + Traefik webhook middlewares; KEDA (Kafka-lag).
7. **GitOps last:** argo-cd stepwise 7→10 (highest-risk; do when the rest is stable).
</content>
