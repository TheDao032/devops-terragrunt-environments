locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  org_config_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org_name        = local.org_config_vars.locals.infras_organization

  vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault.hcl"))
  vault_address     = local.vault_config_vars.locals.vault_address # host-side (vault.k3s.fitmate) — NOT resolvable from inside the cluster

  # In-cluster Vault address for the ESO SecretStore. External Secrets runs as a POD, so it must use
  # cluster DNS (CoreDNS), NOT the host-only `vault.k3s.prod` ingress hostname (pods can't resolve
  # it → "no such host" → InvalidProviderConfig). vault-active = the unsealed active node; HTTPS on
  # 8200. The ESO controller runs with VAULT_SKIP_VERIFY=true, so the cert-manager private CA needs
  # no caBundle here (lab); for prod, add caProvider → the vault-tls-ca secret instead.
  vault_incluster_address = "https://vault-active.vault.svc.cluster.local:8200"

  # Keycloak connects to the EXTERNAL Citus Postgres coordinator DIRECT (:5432, NOT pgbouncer —
  # its schema migrations take advisory locks that transaction pooling breaks).
  pg_host = get_env("PG_HOST", "192.168.105.10")

  # Cluster-wide hostname suffix for the shared platform services (one Vault/ArgoCD/Keycloak).
  # NOT k3s.<env> — these are single instances. Per-env APP hosts are <app>.<env>.k3s.fitmate.
  cluster_suffix = local.environment_vars.locals.cluster_suffix

  # secret_store_name = "vault-backend"
  # secrets          = local.environment_vars.locals.secrets
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/${local.org_name}/ops-tools"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/${local.org_name}/k3s-resources?ref=${local.environment}"
}

# STANDALONE PROD (2026-08-04, [[production-cloudflare-tunnel]]): this cluster IS prod — it deploys its
# OWN ArgoCD here (it then syncs the fitmate-prod AppProject + root-prod from fitmate-gitops PR #6).
# Gate on Vault reachability (ops-tools reads vault-auths/vault-secrets outputs + the vault provider):
# curl fails while Vault is down/sealed → exclude; 200 → include. Applied automatically once Vault is up.
exclude {
  if = run_cmd("--terragrunt-quiet", "bash", "-c",
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.fitmate}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "kube" {
  path = find_in_parent_folders("kube.hcl")
}


dependency "vault-auths" {
  config_path = "../vault-auths"
  mock_outputs = {
    kv_mount_path = "mock"
    roles = {
      external-secrets = {
        role_id      = "mock",
        secret_id    = "mock",
        client_token = "mock"
      }
    }
  }

  # Mocks used ONLY for validate/plan (never apply → a real apply can't write "MOCK" values).
  # deep_map_only fills MISSING SUB-KEYS inside an existing map output (a newly-added secret key),
  # so `run --all -- plan` works before the dependency is re-applied. Apply needs real outputs.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "deep_map_only"
}

# ArgoCD reads GitHub/ArgoCD creds from vault-secrets and the ESO SecretStore name from
# external-secrets. mock_outputs let the FIRST bring-up pass plan (ArgoCD off) before those
# stacks exist; the SECOND pass (ArgoCD on) uses their real, applied outputs. Apply order:
#   k3s-resources (argocd_conf absent) → vault-secrets → external-secrets → k3s-resources (this).
dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    secrets = {
      "github/params"               = { url = "https://github.com/FITMate-Platform", gitops_repo = "fitmate-gitops" }
      "github/creds"                = { ssh_priv_key = "MOCK", username = "MOCK", token = "MOCK" }
      "argocd/creds"                = { password = "MOCK", password_bcrypt = "MOCK" }
      "database/keycloak/app/creds" = { username = "keycloak_app", password = "MOCK" }
      "keycloak/admin/creds"        = { username = "admin", password = "MOCK" }
      "kafka/creds"                 = { clientUsername = "admin", clientPassword = "MOCK" }
      "redis/creds"                 = { password = "MOCK" }
      "grafana/creds"               = { username = "admin", password = "MOCK" }
    }
  }

  # Mocks used ONLY for validate/plan (never apply → a real apply can't write "MOCK" values).
  # deep_map_only fills MISSING SUB-KEYS inside an existing map output (a newly-added secret key),
  # so `run --all -- plan` works before the dependency is re-applied. Apply needs real outputs.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "deep_map_only"
}

# ORDERING-ONLY edge (`dependencies`, plural — no output fetch). ops-tools deploys Keycloak, which
# needs its Postgres DB (db `keycloak`, role `keycloak_app`) provisioned FIRST. Those creds come from
# Vault (the vault-secrets dependency above), NOT from this unit's outputs — so we only need the
# run-ORDER, not data. `database/` is a PARENT FOLDER (holds database.hcl + per-service sub-units),
# not a unit itself → config_path="../database" errors "no terragrunt.hcl"; depend on the SUB-UNIT.
# (ArgoCD needs no service DB; app DBs like trainee are consumed by gitops-deployed pods, not here.)
dependencies {
  paths = ["../database/keycloak"]
}

# dependency "external-secrets" {
#   config_path = "../external-secrets"
#   mock_outputs = {
#     gitops_backend_name = "gitops-backend"
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }

inputs = {
  # Keycloak (operator). Present ⇒ addons.tf enables the keycloak + keycloak-routing modules.
  # DB = EXTERNAL Citus Postgres, coordinator DIRECT :5432 (db `keycloak`, role keycloak_app from
  # Vault via vault-secrets). Routing = Gateway API HTTPRoute on the traefik-gateway `web` listener
  # → the operator's keycloak-service :8080. CRDs come from init-resources; apply that stack first.
  keycloak_conf = {
    keycloak = {
      # ⚠️ `hostname` is now only a FALLBACK. With hostname_dynamic = true below, Keycloak omits the
      # fixed hostname and derives the frontend URL — and therefore the `iss` claim on every token —
      # from the request's X-Forwarded-Host (honoured via the CR's `proxy.headers: xforwarded`).
      # Kept because flipping hostname_dynamic back to false must restore the previous behaviour
      # exactly.
      hostname = "keycloak.k3s.${local.cluster_suffix}"

      # IN-15 phase 2. ONE Keycloak serves dev/stg/prod, so a pinned hostname forced every realm to
      # stamp the same issuer — which is why the prod overlays' expected
      # https://auth.fitmate.me/realms/fitmate cannot match (fitmate-gitops
      # apps/trainee-service/prod/values.yaml:55-58), and why IN-14's social-login broker callbacks
      # are unregisterable (Google/Facebook require https; keycloak.k3s.fitmate is plain HTTP).
      #
      # NOT A CUTOVER. Requests still arriving on keycloak.k3s.fitmate derive a byte-identical
      # issuer, so nothing currently working changes. This only ADDS the ability for additional
      # hosts to issue their own correct issuer once they are routed (phase 3).
      #
      # Baseline captured before enabling, to be re-checked after apply — these must be UNCHANGED:
      #   fitmate-dev -> http://keycloak.k3s.fitmate/realms/fitmate-dev
      #   fitmate-stg -> http://keycloak.k3s.fitmate/realms/fitmate-stg
      # Verify with the realm's own discovery doc, not by reading this file:
      #   curl -s http://keycloak.k3s.fitmate/realms/fitmate-dev/.well-known/openid-configuration | jq -r .issuer
      #
      # ⚠️ SECURITY: dynamic resolution trusts the proxy — Keycloak believes whatever Host /
      # X-Forwarded-Host it receives, so `iss` is attacker-influenced if an arbitrary Host can reach
      # it. Safe here ONLY because Traefik routes by Gateway API HTTPRoute `hostnames` and an
      # unlisted Host does not route. Adding a hostname to that route is a SECURITY decision.
      # Never add a wildcard hostname to the Keycloak HTTPRoute.
      hostname_dynamic = true

      namespace = "keycloak"
      instances = 1

      # ── Branded login theme (spec 067 / SCRUM-245, T052 + T053a) ─────────────────────────────
      # 🔴 COMMENTED ON PURPOSE — DO NOT UNCOMMENT UNTIL THE IMAGE IS ACTUALLY PUBLISHED AND
      # PULLABLE. This is one Keycloak serving fitmate-dev, fitmate-stg AND prod; pointing it at a
      # tag that does not exist is not a no-op, it is ImagePullBackOff on the only auth server all
      # three realms use. Verify the tag resolves first:
      #     docker manifest inspect ghcr.io/fitmate-platform/fitmate-keycloak:<tag> > /dev/null && echo OK
      #
      # The image is built by the FITMate repo (services/front-end/fitmate-website/keycloak-theme,
      # `make image` / `make deploy`), because that is where the theme source and its Tailwind/token
      # inputs live. Infra consumes a tag; it does not build one. Pin an IMMUTABLE tag (the commit
      # sha the Makefile defaults to), never `latest` — the tag IS the deploy unit here.
      #
      # ⚠️ VERSION ALIGNMENT: the custom image's Keycloak base MUST match the operator (26.7.0
      # today). The operator and server are upgraded together; a pinned custom image is not, so
      # this becomes a standing rebuild obligation on every Keycloak bump.
      image = "ghcr.io/fitmate-platform/fitmate-keycloak:d2d2682"
      #
      # Only if the GHCR package is PRIVATE. The Secret must already exist in the `keycloak`
      # namespace — nothing here creates it (the existing `ghcr-pull` Secrets live in the
      # fitmate-*-dev namespaces, NOT in `keycloak`). Publishing the package publicly is simpler
      # and leaks nothing: the image is a stock Keycloak plus a CSS/JS theme.
      # image_pull_secret = "ghcr-pull"
      #
      # Theme caching. RUNTIME options (verified: only SPI names ending in --provider, --enabled or
      # --provider-default are build-time), so they belong here on the CR rather than in the image.
      #
      # ⚠️ SERVER-WIDE, NOT PER-REALM. These slow theme rendering for EVERY realm on this instance,
      # prod included — there is no per-realm theme cache. Keycloak's own docs warn this "will
      # significantly impact performance".
      #
      # ⚠️ AND THEY ARE PROBABLY NOT WHAT MAKES A REDEPLOY VISIBLE. cache-themes/cache-templates are
      # in-JVM caches, so a new image tag already empties them by rolling the pod. The one that
      # genuinely matters is static-max-age: it sets the BROWSER Cache-Control on theme assets and
      # defaults to 2592000 (30 days), while the /resources/<hash>/ path segment is the Keycloak
      # RESOURCES version — it does NOT change when only the theme changes. So without this, an
      # already-visited browser can hold stale CSS for a month across theme updates.
      # A value <= 0 makes Keycloak send `no-cache` instead of a max-age.
      #
      # RECOMMENDATION: enable while the theme is being iterated, then delete this block once it
      # stabilises and let the image tag be the cache-bust.
      # additional_options = {
      #   "spi-theme--cache-themes"    = "false"
      #   "spi-theme--cache-templates" = "false"
      #   "spi-theme--static-max-age"  = "-1"
      # }
    }
    db = {
      host     = local.pg_host
      port     = 5432
      database = "keycloak"
      username = dependency.vault-secrets.outputs.secrets["database/keycloak/app/creds"]["username"]
      password = dependency.vault-secrets.outputs.secrets["database/keycloak/app/creds"]["password"]
    }
    admin = {
      username = dependency.vault-secrets.outputs.secrets["keycloak/admin/creds"]["username"]
      password = dependency.vault-secrets.outputs.secrets["keycloak/admin/creds"]["password"]
    }
    routing = {
      httproutes = [
        # ── ONE ROUTE PER HOSTNAME, each PINNING its own forwarded headers (IN-20) ──────────────
        #
        # This used to be a single route listing all three hostnames, with a comment claiming the
        # hostname list was "the ONLY thing stopping host-header injection from forging an issuer".
        # That claim was TESTED ON 2026-08-23 AND IS FALSE, so do not restore it:
        #
        #   the allow-list gates the `Host` header. Keycloak derives `iss` from `X-Forwarded-Host`.
        #   Those are different headers, and nothing forced them to agree.
        #
        # A request with a legal `Host` (so it routes) and a forged `X-Forwarded-Host` (so Keycloak
        # believes it) produced, from a laptop with NO cluster access:
        #
        #   curl -H "Host: auth-dev.fitmate.me" -H "X-Forwarded-Host: evil.attacker.example" \
        #        http://<traefik-lb>/realms/fitmate-dev/.well-known/openid-configuration
        #   -> "issuer": "https://evil.attacker.example/realms/fitmate-dev"
        #
        # Traefik was supposed to reject those headers from untrusted sources — trustedIPs is the
        # pod CIDR — but k3s serves type=LoadBalancer through klipper (svclb) pods that SNAT every
        # external packet into that CIDR. So "trust in-cluster callers" really means "trust anyone
        # who can reach the LB IP", and the config gives no hint of it.
        #
        # The fix is to stop deciding whose headers to trust and pin them per hostname instead.
        # `set` overwrites whatever arrived, so a forged value cannot survive.
        #
        # ⚠️ ONE hostname per route is REQUIRED, not stylistic — the module validates it. A route
        # pinning X-Forwarded-Host for two hostnames would stamp the second with the first's
        # identity. To publish a new host, ADD A ROUTE; never append to an existing route's list.
        # NEVER use a wildcard hostname.
        {
          # In-cluster/lab access. Deliberately pinned to http: nothing serves TLS inside the
          # cluster, and per ADR 2026-08-23-public-host-is-canonical-token-issuer this host must
          # not mint user tokens anyway. Terraform's keycloak provider and JWKS fetches use it.
          name              = "keycloak-cluster"
          namespace         = "keycloak"
          gateway_name      = "traefik-gateway"
          gateway_namespace = "traefik"
          section_name      = "web"
          # Deliberately NOT attached to `websecure`: nothing serves this name over TLS, and a
          # listener advertising it would hand out an issuer for a scheme that does not exist here.
          hostnames    = ["keycloak.k3s.${local.cluster_suffix}"]
          path_prefix  = "/"
          backend_name = "keycloak-service"
          backend_port = 8080
          request_headers = {
            "X-Forwarded-Host"  = "keycloak.k3s.${local.cluster_suffix}"
            "X-Forwarded-Proto" = "http"
            # Port must be pinned alongside Proto — see the auth-dev route for why. 80 is the
            # default for http, so Keycloak omits it: iss = http://keycloak.k3s.fitmate/...
            "X-Forwarded-Port" = "80"
          }
        },
        {
          # dev public host, reached via dev's own Cloudflare tunnel (Access-gated).
          # Pinning Proto=https does double duty: it is the correct value for browser traffic
          # (Cloudflare terminates TLS), AND it makes split-horizon DNS viable for IN-16 — an
          # in-cluster pod calling http://auth-dev.fitmate.me would otherwise get an http issuer
          # and mismatch the https one a browser login produces.
          name              = "keycloak-auth-dev"
          namespace         = "keycloak"
          gateway_name      = "traefik-gateway"
          gateway_namespace = "traefik"
          # BOTH listeners (IN-16 stage 2). `web` carries browser traffic arriving via
          # Cloudflare -> cloudflared (plain HTTP); `websecure` carries in-cluster callers that
          # resolve this hostname to Traefik and connect over real TLS. Attaching to only one means
          # the other path 404s while the Gateway, the route and the pods all report healthy.
          section_names = ["web", "websecure"]
          hostnames     = ["auth-dev.fitmate.me"]
          path_prefix   = "/"
          backend_name  = "keycloak-service"
          backend_port  = 8080
          request_headers = {
            "X-Forwarded-Host"  = "auth-dev.fitmate.me"
            "X-Forwarded-Proto" = "https"
            # ⚠️ PINNING Proto WITHOUT Port PRODUCES A BROKEN ISSUER. Keycloak builds the issuer
            # from Host + Proto + PORT, and includes the port whenever it is not the default for
            # the scheme. Traefik's web entrypoint is :80, so pinning only Proto=https yielded
            #     https://auth-dev.fitmate.me:80/realms/fitmate-dev
            # which fails the services' byte-for-byte issuer check exactly like the original
            # IN-16 mismatch. 443 is the default for https, so pinning it makes Keycloak omit it:
            #     https://auth-dev.fitmate.me/realms/fitmate-dev
            "X-Forwarded-Port" = "443"
          }
        },
        {
          name              = "keycloak-auth-stg"
          namespace         = "keycloak"
          gateway_name      = "traefik-gateway"
          gateway_namespace = "traefik"
          # BOTH listeners (IN-16 stage 2). `web` carries browser traffic arriving via
          # Cloudflare -> cloudflared (plain HTTP); `websecure` carries in-cluster callers that
          # resolve this hostname to Traefik and connect over real TLS. Attaching to only one means
          # the other path 404s while the Gateway, the route and the pods all report healthy.
          section_names = ["web", "websecure"]
          hostnames     = ["auth-stg.fitmate.me"]
          path_prefix   = "/"
          backend_name  = "keycloak-service"
          backend_port  = 8080
          request_headers = {
            "X-Forwarded-Host"  = "auth-stg.fitmate.me"
            "X-Forwarded-Proto" = "https"
            "X-Forwarded-Port"  = "443"
          }
        },
      ]
    }
  }

  # ArgoCD (core). Present ⇒ addons.tf enables the argocd + argocd-routing modules (see the
  # two-pass note there). Reads live creds/store name from the vault-secrets + external-secrets
  # dependency blocks below (mocked so the first bring-up pass still plans while ArgoCD is off).
  argocd_conf = {
    helm = {
      # Latest argo-helm chart (2026-07-09). NOTE: 3-major jump from the old 7.8.10 scaffold —
      # our values only touch stable keys (server.insecure, credentialTemplates, repositories),
      # but skim the 8.0.0 / 9.0.0 / 10.0.0 breaking-change notes before the prod tenants adopt it.
      chart_version = "10.1.3"
      namespace     = "argocd"
      repository    = "https://argoproj.github.io/argo-helm"
      release_name  = "argo-cd"
    }

    # Only `domain` is consumed (values.yml.tftpl global.domain). Routing is Gateway API below.
    ingress = {
      domain = "argocd.k3s.${local.cluster_suffix}"
    }

    # Names for the chart's ExternalSecrets (applied after the release; reconcile once the gitops
    # SecretStore exists). store_name = the ESO SecretStore in the gitops ns (external-secrets stack).
    secret = {
      vault_address       = local.vault_incluster_address                                      # in-cluster (ESO pod) — NOT vault.k3s.prod
      kv_mount            = dependency.vault-auths.outputs.kv_mount_path                       # org KV mount ("fitmate") the SecretStore reads FROM (was hardcoded to the env "local")
      approle_path        = "approle"                                                          # auth mount (vault_auth_backend.main default path)
      role_id             = dependency.vault-auths.outputs.roles["external-secrets"].role_id   # public
      secret_id           = dependency.vault-auths.outputs.roles["external-secrets"].secret_id # credential
      approle_secret_name = "argocd-approle"
      argocd_secret_name  = "argocd-ex-secret"

      store_name                = "argocd-store-backend"
      docker_config_secret_name = "docker-ex-configjson"
      docker_token_secret_name  = "docker-ex-token"
      github_secret_name        = "github-ex-ssh-priv-key"
    }

    github = {
      url         = dependency.vault-secrets.outputs.secrets["github/params"]["url"]
      gitops_repo = dependency.vault-secrets.outputs.secrets["github/params"]["gitops_repo"]
      # HTTPS auth for the private fitmate-gitops repo — username + read PAT (ssh_priv_key retired with
      # the old SSH repo). ArgoCD's https-creds credentialTemplate consumes these.
      username = dependency.vault-secrets.outputs.secrets["github/creds"]["username"]
      token    = dependency.vault-secrets.outputs.secrets["github/creds"]["token"]
    }

    common = {
      admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password_bcrypt"]
    }

    # UI/API via Gateway API HTTPRoute on the shared traefik-gateway `web` listener. HTTPRoute
    # lives in `argocd` (same ns as the backend Service → no ReferenceGrant); parentRef crosses
    # into `traefik` (allowed, listener is from:All). backend_name = the argocd-server Service.
    # CONFIRMED via `kubectl get svc -n argocd`: chart names it `<release>-argocd-server` →
    # release `argo-cd` yields `argo-cd-argocd-server` (Service port http:80).
    routing = {
      httproutes = [
        {
          name              = "argocd"
          namespace         = "argocd"
          gateway_name      = "traefik-gateway"
          gateway_namespace = "traefik"
          section_name      = "web"
          hostnames         = ["argocd.k3s.${local.cluster_suffix}"]
          path_prefix       = "/"
          backend_name      = "argo-cd-argocd-server"
          backend_port      = 80
        }
      ]
    }
  }

  # argocd_img_upd_conf = {
  #   helm = {
  #     chart_version = "1.2.4"
  #     namespace     = "argocd"
  #     repository    = "https://argoproj.github.io/argo-helm"
  #     release_name  = "argocd-image-updater"
  #   }
  #
  #   docker = {
  #     secret_name  = "docker-ex-token"
  #     organization = dependency.vault-secrets.outputs.secrets["docker/creds"]["username"]
  #   }
  #
  #   common = {
  #     admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password"]
  #   }
  # }
  #
  # Kafka (Bitnami Apache Kafka, KRaft, IN-CLUSTER ONLY). Present ⇒ addons.tf enables the kafka
  # module. Right-sized for the lab (~1–2Gi free/node): KRaft COMBINED (controllerOnly=false), a
  # SINGLE controller node, HPA OFF, resourcesPreset=small + heap 512m, 2Gi storage. externalAccess
  # is DISABLED in the values template — consumers reach the broker via cluster DNS at
  # kafka.tools.svc.cluster.local:9092. SASL user `admin`, password from Vault kafka/creds.
  kafka_conf = {
    helm = {
      chart_version = "32.4.3"

      namespace = "kafka"
      # Bitnami charts moved to OCI (Aug-2025 deprecation). Pulling from the OCI registry gets the
      # self-contained packaged artifact (bundles common@2.31.4) by exact tag — so helm provider
      # v2.16 installs the bundled deps and never re-resolves the Chart.yaml `common: 2.x.x` OCI range
      # (which it can't → `invalid_reference: invalid tag`). See the HTTP-repo failure.
      repository   = "oci://registry-1.docker.io/bitnamicharts"
      release_name = "kafka"
    }

    # Single combined KRaft controller/broker. HPA OFF (min/max still render but are inert while
    # hpa_active=false). 2Gi on the k3s `local-path` StorageClass.
    controller = {
      replica_count = 1
      hpa_active    = false
      mount_path    = "/bitnami/kafka/controller"
      size          = "2Gi"
      min_replicas  = 1
      max_replicas  = 1
    }

    # NOTE: no `broker` block. KRaft combined mode uses ONLY the controller pool (controllerOnly=false),
    # so dedicated brokers are 0 and the values template's broker section stays commented out.

    sasl = {
      client_username = dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientUsername"]
      client_password = dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientPassword"]
    }

    # sc_name = the k3s built-in local-path StorageClass (already the cluster default). The values
    # template points global.storageClass + controller.persistence.storageClass at it; PVCs bind to
    # the existing SC (no new StorageClass is created — the chart's sc.yml.tftpl was removed).
    common = {
      sc_name = "local-path"
    }
  }

  # Redis (Bitnami Redis, STANDALONE, IN-CLUSTER ONLY). Present ⇒ addons.tf enables the redis module.
  # Right-sized for the lab: a SINGLE master, 0 replicas, resourcesPreset=small, 1Gi PVC on the k3s
  # `local-path` StorageClass. externalAccess is disabled in the values template — consumers reach
  # Redis via cluster DNS at redis-redis-master.tools.svc.cluster.local:6379. Auth ON; the `default`
  # user's password comes from Vault redis/creds. Re-apply vault-secrets BEFORE ops-tools.
  redis_conf = {
    helm = {
      chart_version = "27.0.18"

      namespace    = "redis"
      repository   = "oci://registry-1.docker.io/bitnamicharts"
      release_name = "redis"
    }

    # Single master (standalone). 1Gi on the k3s `local-path` StorageClass.
    master = {
      size = "1Gi"
    }

    # Redis default user is `default`; this password is its AUTH password (from Vault redis/creds).
    auth = {
      password = dependency.vault-secrets.outputs.secrets["redis/creds"]["password"]
    }

    # sc_name = the k3s built-in local-path StorageClass (already the cluster default). The values
    # template points global.storageClass + master.persistence.storageClass at it; the PVC binds to
    # the existing SC (no new StorageClass is created — the chart has no sc.yml.tftpl, same as kafka).
    common = {
      sc_name = "local-path"
    }
  }

  # ── Observability: kube-prometheus-stack (IN-13) ──────────────────────────────────────────────
  # Dev had NO observability: every service already exposed Prometheus metrics and every gitops
  # overlay carried `serviceMonitor: enabled: false  # TEMP: no Prometheus Operator on-cluster yet`.
  # Instrumentation complete, nothing scraping it — which is why every incident this month was
  # diagnosed by hand-reading pod logs, and why SCRUM-234 (Kafka consumption dead platform-wide)
  # went unnoticed for weeks when consumer lag would have shown it in a day.
  #
  # Chart 88.5.2 / appVersion v0.93.1 (resolved from the live repo, not guessed).
  #
  # ⚠️ FLAT STRING VALUES ONLY — shared/helm declares `variable "parameters"` as `map(any)`, and
  # map(any) unifies ALL elements to one type. Nested resource blocks of differing shapes fail with
  # "all map elements must have the same type". Every other chart here (redis, kafka) passes flat
  # map(string) sub-maps for the same reason. Do not reintroduce nested `resources { requests {...} }`,
  # and do not add a top-level scalar beside these three maps.
  prometheus_conf = {
    helm = {
      chart_version = "88.5.2"

      namespace  = "monitoring"
      repository = "https://prometheus-community.github.io/helm-charts"
      # ⚠️ release_name MUST equal the upstream CHART name. shared/helm does
      #   chart = coalesce(local.chart, var.name)
      # so with no local chart, var.name IS the chart pulled from the repo — and it also selects the
      # values dir charts/<name>/. Naming this "prometheus" resolved to prometheus-community's
      # STANDALONE `prometheus` chart -> "Error locating chart". The values dir was renamed to match.
      release_name = "kube-prometheus-stack"
    }

    # ⚠️ LIMITS ARE LOAD-BEARING, NOT HYGIENE. Schedulable capacity is 3 agents x 2 vCPU / 2962Mi
    # (both servers control-plane tainted), ~51% used, with 5 more services still to onboard. The
    # chart's own defaults are sized for production clusters; an unbounded Prometheus on a 2.9Gi
    # node evicts its neighbours. Sized for the few thousand active series this lab actually has;
    # whole stack lands ~1-1.8Gi. Raise ONLY from measured numbers.
    # ⚠️ retention_size and storage_size MOVE TOGETHER. local-path does not enforce PVC size (it
    # bind-mounts a node dir), so storage_size is documentation and retention_size is the real
    # bound. Raising storage_size alone changes nothing; raising retention_size alone lets
    # Prometheus eat the node root fs until DiskPressure evicts its neighbours.
    # Official rule: retention_size <= 80-85% of storage_size (the rest is compaction scratch).
    # 30d x ~0.45 GB/day = ~13.5GB of blocks; 16GB cap on a 20Gi PVC = 80%. See IN-25.
    # local-path has ALLOWVOLUMEEXPANSION: false -> this cannot be grown in place. Sized once,
    # after the guest disks went 40G -> 100G on 2026-08-25.
    prometheus = {
      ingress_prefix = "/"
      retention      = "30d"  # was 7d; the 40G guest disk was the cap, not the workload
      retention_size = "16GB" # hard stop that protects the node as series grow
      storage_size   = "20Gi"
      storage_class  = "local-path"
      cpu_request    = "100m"
      memory_request = "512Mi"
      cpu_limit      = "1000m"
      memory_limit   = "1Gi"
    }

    # Admin password from Vault platform/grafana/creds. The chart default is the well-known literal
    # `prom-operator`, and Grafana is published on a routable hostname below — so the default would
    # be a cluster-wide credential sitting on the network.
    # `loki_url` is intentionally omitted (no Loki on this cluster); the template renders the Loki
    # datasource only when it is present.
    # ⚠️ Grafana's CPU limit is deliberately GENEROUS. 300m throttled it into a 5-restart crash loop:
    # CPU sat pegged at exactly 300m, Grafana never opened :3000 in time, and the livenessProbe killed
    # it mid-boot ("connection refused", reason=Error exit=1 — NOT OOMKilled). Grafana 13.x registers
    # ~10 *.grafana.app API groups at startup, then idles near 0. Only REQUESTS are reserved by the
    # scheduler, so a high limit with a low request is free burst headroom. Tight limits are a memory
    # discipline, not a CPU one. The values template also adds a startupProbe so liveness stops
    # policing boot. Steady-state observed: ~218Mi, so 384Mi limit leaves real headroom over 256Mi.
    # storage_size is deliberately SMALL. Dashboards arrive as sidecar ConfigMaps and datasources
    # are provisioned, so none of that needs a disk. What this preserves is the state Grafana alone
    # owns and code cannot rebuild: annotations (incident markers), users/preferences, starred
    # dashboards, Explore history. Omitting the key entirely reverts to stateless.
    # A ReadWriteOnce PVC pins Grafana to one node and caps it at one replica — fine for a single
    # -replica dev lab. In prod use an external Postgres instead; that is what allows HA.
    grafana = {
      password       = dependency.vault-secrets.outputs.secrets["grafana/creds"]["password"]
      ingress_prefix = "/"
      storage_size   = "2Gi"
      storage_class  = "local-path"
      cpu_request    = "100m"
      memory_request = "192Mi"
      cpu_limit      = "1000m"
      memory_limit   = "384Mi"
    }

    # Rules evaluate from day one; DELIVERY (Telegram/Slack) is wired LAST, deliberately. An
    # unrouted alert still fires and still shows in the UI, which is what proves the rule works.
    alertmanager = {
      cpu_request    = "20m"
      memory_request = "64Mi"
      cpu_limit      = "150m"
      memory_limit   = "128Mi"
    }

    # Grafana UI via Gateway API HTTPRoute on the shared traefik-gateway `web` listener, same shape
    # as argocd/keycloak. Backend is plain HTTP :80, so no BackendTLSPolicy — which also avoids the
    # Traefik GW API hostname-verification bug that blocks HTTPS re-encryption.
    #
    # CONFIRMED by `helm template` against chart 88.5.2: release `kube-prometheus-stack` renders the
    # Grafana Service as `kube-prometheus-stack-grafana`, port http-web:80. Re-verified after the
    # rename below — the service name is derived from the RELEASE name, so it moved with it.
    routing = {
      httproutes = [
        {
          name              = "grafana"
          namespace         = "monitoring"
          gateway_name      = "traefik-gateway"
          gateway_namespace = "traefik"
          section_name      = "web"
          hostnames         = ["grafana.k3s.${local.cluster_suffix}"]
          path_prefix       = "/"
          backend_name      = "kube-prometheus-stack-grafana"
          backend_port      = 80
        },

        # ── Prometheus + Alertmanager UIs ────────────────────────────────────────────────────────
        #
        # Added because their absence was the ONLY reason `kubectl port-forward` kept appearing in
        # runbooks and ticket text. `/etc/hosts` already resolved both names to the Traefik LB long
        # before this existed — the missing half was always the route, so the symptom was a Traefik
        # 404 (request arrived, no HTTPRoute matched the Host) rather than a DNS failure. Those two
        # look nothing alike once you know, and identical before you do:
        #
        #   Host: grafana.k3s.fitmate       -> 302   (route exists)
        #   Host: prometheus.k3s.fitmate    -> 404   (name resolved, nothing routed it)
        #
        # Backends are plain-HTTP ClusterIP, so no BackendTLSPolicy — which also avoids the Traefik
        # Gateway-API hostname-verification bug that blocks verified HTTPS re-encryption.
        #
        # Service names + ports CONFIRMED against the live cluster (not inferred from the chart):
        #   kube-prometheus-stack-prometheus     http-web:9090
        #   kube-prometheus-stack-alertmanager   http-web:9093
        # Both are derived from the RELEASE name, so they move if the release is ever renamed.
        #
        # ⚠️ SECURITY — READ BEFORE EXTENDING THIS.
        # Neither UI has ANY authentication of its own. Grafana at least has a login; these do not.
        # Anything that can reach the Traefik LB IP with the right Host header gets:
        #   Prometheus    — every metric, every label value, and the full scrape/target config
        #   Alertmanager  — alert contents AND the ability to CREATE SILENCES, i.e. an unauthenticated
        #                   party can suppress alerting for the whole cluster
        # That is acceptable ONLY because these are lab-internal `.k3s.<suffix>` names on the `web`
        # listener, reachable from the LAN and not published through Cloudflare.
        #
        # 🔴 DO NOT attach these to a PUBLIC hostname or to `websecure` for external use, and do not
        # add them to the Cloudflare tunnel, without putting Cloudflare Access (or equivalent) in
        # front — the way ../../<env>/cloudflare-access gates auth-<env>.fitmate.me. Publishing an
        # unauthenticated Alertmanager is strictly worse than having no alerting, because silences
        # fail closed and silently.
        {
          name              = "prometheus"
          namespace         = "monitoring"
          gateway_name      = "traefik-gateway"
          gateway_namespace = "traefik"
          section_name      = "web"
          hostnames         = ["prometheus.k3s.${local.cluster_suffix}"]
          path_prefix       = "/"
          backend_name      = "kube-prometheus-stack-prometheus"
          backend_port      = 9090
        },
        {
          # Needed for IN-27: the plan is to watch rules go Pending -> Firing in this UI BEFORE any
          # delivery channel is chosen. Without a reachable Alertmanager that workflow cannot happen.
          name              = "alertmanager"
          namespace         = "monitoring"
          gateway_name      = "traefik-gateway"
          gateway_namespace = "traefik"
          section_name      = "web"
          hostnames         = ["alertmanager.k3s.${local.cluster_suffix}"]
          path_prefix       = "/"
          backend_name      = "kube-prometheus-stack-alertmanager"
          backend_port      = 9093
        }
      ]
    }
  }

}
