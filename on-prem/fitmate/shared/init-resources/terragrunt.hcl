locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  org_config_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org_name        = local.org_config_vars.locals.infras_organization

  vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault.hcl"))
  vault_address     = local.vault_config_vars.locals.vault_address # host-side (vault.k3s.prod) — NOT resolvable from inside the cluster

  # In-cluster Vault address for the ESO SecretStore. External Secrets runs as a POD, so it must use
  # cluster DNS (CoreDNS), NOT the host-only `vault.k3s.prod` ingress hostname (pods can't resolve
  # it → "no such host" → InvalidProviderConfig). vault-active = the unsealed active node; HTTPS on
  # 8200. The ESO controller runs with VAULT_SKIP_VERIFY=true, so the cert-manager private CA needs
  # no caBundle here (lab); for prod, add caProvider → the vault-tls-ca secret instead.
  vault_incluster_address = "https://vault-active.vault.svc.cluster.local:8200"

  # secret_store_name = "vault-backend"
  # secrets          = local.environment_vars.locals.secrets
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/${local.org_name}/init-resources"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/${local.org_name}/k3s-resources?ref=${local.environment}"
}

# SHARED PLATFORM (single-cluster, multi-env): this is the ONE cluster platform for all envs
# (dev/stg/prod). It stands up Vault, CRDs, External-Secrets, Traefik and cert-manager once —
# there is no per-env init-resources anymore. Applied first; everything else layers on top.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "kube" {
  path = find_in_parent_folders("kube.hcl")
}
inputs = {
  # CoreDNS is managed by k3s itself (rancher/mirrored-coredns-coredns:1.11.3); the lab no
  # longer disables it. The terraform core-dns module is commented out in addons.tf, so this
  # input is disabled too. Re-enable both (with a multi-arch image) only if you re-add
  # --disable=coredns and want terraform to own CoreDNS.
  # coredns_conf = {
  #   helm = {
  #     chart_version = "1.10.101-build2021022303"
  #     namespace     = "kube-system"
  #     repository    = "https://rke2-charts.rancher.io/"
  #     release_name  = "rke2-coredns"
  #   }
  #
  #   common = {
  #   }
  # }

  external_secrets_conf = {
    helm = {
      chart_version = "2.7.0"
      namespace     = "kube-system"
      repository    = "https://charts.external-secrets.io/"
      release_name  = "external-secrets"
    }

    common = {
    }
  }

  # Self-managed Traefik v3 (bundled v2.11 disabled via config.yaml k3s_disable="--disable=traefik").
  # One controller for Kubernetes Ingress (Vault) + Traefik CRD/IngressRoute (dashboard) +
  # Gateway API (future HTTP services). Gateway API standard CRDs are server-side-applied by
  # module "gateway-api-crds"; the traefik.io CRDs come from this chart's own crds/ dir. Vault
  # stays on its Ingress + ServersTransport (NOT Gateway API — traefik/traefik#12127).
  traefik_conf = {
    helm = {
      chart_version = "41.0.2" # latest; app v3.7.6 (verified on artifacthub 2026-07-11)
      namespace     = "traefik"
      repository    = "https://traefik.github.io/charts"
      release_name  = "traefik"
    }

    common = {}

    # Hostnames Traefik must be able to terminate TLS for ITSELF, instead of relying on Cloudflare
    # to do it at the edge (IN-16 follow-up). A cert-manager Certificate is issued per entry into
    # the traefik namespace; the resulting Secret is named after the host with dots replaced.
    #
    # WHY: the website's Auth.js BFF refreshes tokens SERVER-SIDE from inside the cluster, using the
    # issuer URL (https://auth-<env>.fitmate.me). Routed to Cloudflare that pod meets the Access
    # login page instead of a token. Routed to Traefik instead, it needs Traefik to present a cert
    # for that name — otherwise the call dies with "unable to get local issuer certificate", which
    # is a NEW failure wearing the old one's clothes.
    #
    # ⚠️ Nothing consumes these certificates yet. Stage 1 issues them and stops there, so the ACME
    # chain can be proven on its own before any routing or DNS is touched.
    #
    # issuer: the PRODUCTION ClusterIssuer. Changing issuerRef on a Certificate is what triggers
    # cert-manager to re-issue, so moving these from the staging issuer to the production one
    # replaces the untrusted staging certs automatically — no secret deletion, no manual renew.
    public_host_certs = [
      { name = "auth-dev.fitmate.me", issuer = "letsencrypt-dns01-prod" },
      { name = "auth-stg.fitmate.me", issuer = "letsencrypt-dns01-prod" },
    ]

    # Traefik dashboard is now exposed by the CHART's built-in IngressRoute
    # (ingressRoute.dashboard.enabled in charts/traefik/values.yml.tftpl → host traefik.k3s.<env>),
    # so no routing entry is needed here. Add a `routing` block with httproutes /
    # backend_tls_policies if this controller needs Gateway-API routes later.
  }

  # Routing controller for Gateway API routes (future services). Per-app routes live in each
  # app's own `routing` block; Vault has none (it's on an Ingress, not Gateway API).
  route_type = "traefik"

  # ── Split-horizon DNS (IN-16 stage 2) ─────────────────────────────────────────────────────────
  # In-cluster callers resolve the PUBLIC auth hostnames to Traefik instead of Cloudflare, so a pod
  # refreshing a token does not meet the Cloudflare Access login page. The issuer STRING is
  # unchanged, so `iss` still matches what every service is configured to accept.
  #
  # Rewrites to the SERVICE NAME, not a ClusterIP, so it survives Traefik's Service being recreated.
  #
  # ⚠️ This only works because Traefik now serves a real Let's Encrypt certificate for these names
  # (traefik_conf.public_host_certs). Without that, DNS alone sends the pod to a listener presenting
  # TRAEFIK DEFAULT CERT and the call dies on certificate verification instead — a new failure
  # wearing the old one's clothes.
  #
  # ⚠️ This affects EVERY pod resolving these names. That is intended, but it means nothing inside
  # the cluster can reach the Cloudflare path for these hostnames any more — including anything that
  # legitimately wanted the Access gate.
  #
  # ── 🔴 DO NOT DELETE THESE REWRITES: THE WEBSITE'S SIGN-IN DEPENDS ON THEM ────────────────────
  # This block was written for token REFRESH. Since the website was onboarded it carries more than
  # that, and the note above understates it. `services/front-end/fitmate-website/src/auth.ts` makes
  # TWO server-side calls to the public auth host from inside the Next.js pod (named by SYMBOL, not
  # line number, so this survives the file being reformatted):
  #
  #   the `Keycloak({ issuer: AUTH_KEYCLOAK_ISSUER })` provider  OIDC discovery + the
  #                                                              AUTHORIZATION-CODE EXCHANGE
  #   the fetch to `${issuer}/protocol/openid-connect/token`     refresh (in refreshAccessToken)
  #
  # The first runs during INITIAL SIGN-IN. Both are non-browser calls, and auth-<env>.fitmate.me is
  # Cloudflare Access-gated (../../<env>/cloudflare-access), so without these rewrites they meet an
  # Access HTML login page instead of a token endpoint. The consequence is not "sessions stop
  # refreshing" — it is that SIGN-IN NEVER COMPLETES. The browser hop succeeds, the callback lands,
  # and the exchange dies inside the pod.
  #
  # ⚠️ AND IT FAILS SILENTLY. refreshAccessToken ends in a bare `catch { return { ...token, error:
  # 'RefreshAccessTokenError' } }`, so an HTML challenge makes res.json() throw, the catch fires,
  # and the session is marked invalid. What a user reports is "I keep getting randomly signed out."
  # Nothing in any log names Cloudflare, Access, or DNS. Deleting a DNS override and getting random
  # logouts days later is a failure nobody traces back to this file — which is why the warning is
  # here rather than only in a runbook.
  #
  # Verified from inside a pod, 2026-08-24 (the ConfigMap existing proves only that it exists):
  #     nslookup auth-dev.fitmate.me  ->  10.43.85.195   = traefik.traefik ClusterIP
  #
  # ⚠️ The tempting "simplification" is also wrong: do NOT repoint AUTH_KEYCLOAK_ISSUER at an
  # in-cluster host to avoid all this. Keycloak runs hostname.strict=false and derives `iss` from
  # the host it is reached through, and every Go backend compares `iss` byte-for-byte — so that
  # yields a GREEN LOGIN followed by a 401 on the first API call. These rewrites are precisely what
  # lets ONE public issuer string be correct on both the browser and the pod side.
  coredns_custom_conf = {
    rewrites = [
      { from = "auth-dev.fitmate.me", to = "traefik.traefik.svc.cluster.local" },
      { from = "auth-stg.fitmate.me", to = "traefik.traefik.svc.cluster.local" },
    ]
  }

  # Controller + CRDs, self-signed issuers, PLUS an ACME DNS-01 ClusterIssuer (IN-16 follow-up).
  #
  # This block previously said "No ACME/Cloudflare here" because cert-manager deploys BEFORE Vault.
  # That ordering constraint still holds and is exactly why the API token arrives as a Terraform
  # parameter rather than through Vault/ESO — an ESO-delivered secret could not exist yet.
  cert_manager_conf = {
    helm = {
      chart_version = "1.16.1"
      namespace     = "cert-manager"
      repository    = "https://charts.jetstack.io"
      release_name  = "cert-manager"
      values_type   = "controller"
    }

    common = {
      dns01 = {
        enabled = true

        # ⚠️ DEDICATED, NARROWLY-SCOPED TOKEN — Zone:Zone:Read + Zone:DNS:Edit on fitmate.me ONLY.
        # Do NOT substitute CLOUDFLARE_API_TOKEN (the tunnel/Terraform token). That one also holds
        # `Account > Access: Apps and Policies > Edit`, and Cloudflare Access is currently the only
        # control keeping the IN-20 header-forgery hole off the public internet — so a compromised
        # cert-manager pod holding it could delete the policy protecting these very hostnames.
        # Verified 2026-08-23: this token is DENIED on tunnel, access and billing endpoints.
        api_token = get_env("CLOUDFLARE_CERTMANAGER_TOKEN", "")

        email = "nthedao2705@gmail.com"

        # BOTH issuers exist, deliberately. The staging one is not removed after the production one
        # works: it is how any FUTURE certificate gets proven without spending production quota, and
        # deleting it would mean the next person has to rebuild it under time pressure.
        #
        # Staging validated end-to-end 2026-08-23 — order `valid`, Certificate READY, and the issued
        # cert carried CN=auth-dev.fitmate.me, SAN DNS:auth-dev.fitmate.me, issuer
        # "(STAGING) Dastardly Durum YR1". That proved token scope, TXT write, order validation and
        # issuance. The single thing staging CANNOT prove is that a pod trusts the result, which is
        # the whole reason to move to production rather than a reason to have started there.
        #
        # ⚠️ Production has a limit of 50 certificates per registered domain per week. Two hosts is
        # nothing, but re-issuing in a loop while debugging is how that gets spent — debug on
        # staging by pointing a Certificate's issuer back at the staging issuer.
        issuers = [
          {
            name   = "letsencrypt-dns01"
            server = "https://acme-staging-v02.api.letsencrypt.org/directory"
          },
          {
            name   = "letsencrypt-dns01-prod"
            server = "https://acme-v02.api.letsencrypt.org/directory"
          },
        ]

        # Restrict the solver to our zone so a stray Certificate for some other domain cannot
        # quietly consume this issuer.
        zones = ["fitmate.me"]
      }
    }
  }

  vault_conf = {
    helm = {
      chart_version = "0.34.0"
      namespace     = "vault" # isolated ns; cert SANs use <svc>.vault.svc.cluster.local
      repository    = "https://helm.releases.hashicorp.com/"
      release_name  = "vault"
      values_type   = "ha-raft-tls" # → loads values.ha-raft-tls.yml.tftpl
    }

    # server.* → resources + Raft data/audit PVCs in the values template
    server = {
      rq_mem     = "512Mi"
      rq_cpu     = "250m"
      limits_mem = "1Gi"
      limits_cpu = "500m"

      datastore_size       = "10Gi"
      datastore_mount_path = "/vault/datastore" # == storage "raft" path

      auditstore_size       = "10Gi"
      auditstore_mount_path = "/vault/auditstore"
    }

    ui = {
      enabled = true
    }

    common = {
      sc_name               = "vault-sc"          # StorageClass created by sc.yml.tftpl
      vault_service_name    = "vault"             # MUST equal helm.release_name (retry_join + cert SANs)
      vault_tls_server_name = "vault-tls-server"  # cert-manager server-cert secret (mounted)
      vault_tls_ca_name     = "vault-tls-ca"      # cert-manager CA secret
      host                  = "vault.k3s.fitmate" # Traefik ingress host + cert SAN (cluster-wide)
    }

    # NOTE: Vault deliberately stays on the Traefik INGRESS (server.ingress.enabled=true in
    # values.ha-raft-tls.yml.tftpl), NOT Gateway API — so there is intentionally no `routing`
    # block here. Vault is HTTPS-only, so an HTTPRoute would need verified backend
    # re-encryption via BackendTLSPolicy, but Traefik v3.7.6 verifies the backend cert against
    # the pod IP instead of the policy `hostname` (GH traefik/traefik#12127) → always 500. The
    # Ingress path works via a ServersTransport with insecureSkipVerify (keeps Vault's TLS,
    # defense-in-depth intact). Re-add a `routing` block here AND uncomment module
    # "vault-routing" in addons.tf once #12127 is fixed, or after validating NGINX Gateway
    # Fabric honors the BackendTLSPolicy hostname. Other services still use Gateway API.
  }

  # ArgoCD (core). Present ⇒ addons.tf enables the argocd + argocd-routing modules (see the
  # two-pass note there). Reads live creds/store name from the vault-secrets + external-secrets
  # dependency blocks below (mocked so the first bring-up pass still plans while ArgoCD is off).
  # argocd_conf = {
  #   helm = {
  #     # Latest argo-helm chart (2026-07-09). NOTE: 3-major jump from the old 7.8.10 scaffold —
  #     # our values only touch stable keys (server.insecure, credentialTemplates, repositories),
  #     # but skim the 8.0.0 / 9.0.0 / 10.0.0 breaking-change notes before the prod tenants adopt it.
  #     chart_version = "10.1.3"
  #     namespace     = "argocd"
  #     repository    = "https://argoproj.github.io/argo-helm"
  #     release_name  = "argo-cd"
  #   }
  #
  #   # Only `domain` is consumed (values.yml.tftpl global.domain). Routing is Gateway API below.
  #   ingress = {
  #     domain = "argocd.k3s.${local.environment}"
  #   }
  #
  #   # Names for the chart's ExternalSecrets (applied after the release; reconcile once the gitops
  #   # SecretStore exists). store_name = the ESO SecretStore in the gitops ns (external-secrets stack).
  #   secret = {
  #     vault_address       = local.vault_incluster_address                                     # in-cluster (ESO pod) — NOT vault.k3s.prod
  #     approle_path        = "approle"                                                         # auth mount (vault_auth_backend.main default path)
  #     role_id             = dependency.vault-auths.outputs.roles["external-secrets"].role_id   # public
  #     secret_id           = dependency.vault-auths.outputs.roles["external-secrets"].secret_id # credential
  #     approle_secret_name = "argocd-approle"
  #     argocd_secret_name  = "argocd-ex-secret"
  #
  #     store_name                = "argocd-store-backend"
  #     docker_config_secret_name = "docker-ex-configjson"
  #     docker_token_secret_name  = "docker-ex-token"
  #     github_secret_name        = "github-ex-ssh-priv-key"
  #   }
  #
  #   github = {
  #     url          = dependency.vault-secrets.outputs.secrets["github/params"]["url"]
  #     gitops_repo  = dependency.vault-secrets.outputs.secrets["github/params"]["gitops_repo"]
  #     ssh_priv_key = dependency.vault-secrets.outputs.secrets["github/creds"]["ssh_priv_key"]
  #   }
  #
  #   common = {
  #     admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password"]
  #   }
  #
  #   # UI/API via Gateway API HTTPRoute on the shared traefik-gateway `web` listener. HTTPRoute
  #   # lives in `argocd` (same ns as the backend Service → no ReferenceGrant); parentRef crosses
  #   # into `traefik` (allowed, listener is from:All). backend_name = the argocd-server Service.
  #   # CONFIRMED via `kubectl get svc -n argocd`: chart names it `<release>-argocd-server` →
  #   # release `argo-cd` yields `argo-cd-argocd-server` (Service port http:80).
  #   routing = {
  #     httproutes = [
  #       {
  #         name              = "argocd"
  #         namespace         = "argocd"
  #         gateway_name      = "traefik-gateway"
  #         gateway_namespace = "traefik"
  #         section_name      = "web"
  #         hostnames         = ["argocd.k3s.${local.environment}"]
  #         path_prefix       = "/"
  #         backend_name      = "argo-cd-argocd-server"
  #         backend_port      = 80
  #       }
  #     ]
  #   }
  # }

  reloader_conf = {
    helm = {
      chart_version = "2.2.14"
      namespace     = "kube-system"
      repository    = "https://stakater.github.io/stakater-charts"
      release_name  = "reloader"
    }

    common = {
      rq_mem       = "128Mi"
      rq_cpu       = "10m"
      limits_mem   = "512Mi"
      limits_cpu   = "100m"
      storage_size = "10Gi"
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
  # kafka_conf = {
  #   helm = {
  #     chart_version = "31.0.0"
  #     image_tag     = "3.9.0-debian-12-r1"
  #     namespace     = "tools"
  #     repository    = "https://charts.bitnami.com/bitnami"
  #     release_name  = "kafka"
  #   }
  #
  #   controller = {
  #     replica_count = 1
  #     hpa_active    = true
  #     mount_path    = "/bitnami/kafka/controller"
  #     size          = "8Gi"
  #     min_replicas  = 1
  #     max_replicas  = 5
  #   }
  #
  #   broker = {
  #     replica_count = 1
  #     hpa_active    = true
  #     mount_path    = "/bitnami/kafka/broker"
  #     size          = "8Gi"
  #     min_replicas  = 1
  #     max_replicas  = 5
  #   }
  #
  #   sasl = {
  #     client_username : dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientUsername"]
  #     client_password : dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientPassword"]
  #   }
  #
  #   common = {
  #   }
  # }
  #

  # nginx_gateway_fabric_conf = {
  #   helm = {
  #     chart_version      = "1.6.2"
  #     namespace          = "nginx-gateway"
  #     repository    = "oci://ghcr.io/nginx/charts/nginx-gateway-fabric"
  #     release_name  = "ngf"
  #   }
  #
  #   image = {
  #     tag = "nthedao.info"
  #   }
  # }
  #
  # traefik_gateway_api_conf = {
  # }

}
