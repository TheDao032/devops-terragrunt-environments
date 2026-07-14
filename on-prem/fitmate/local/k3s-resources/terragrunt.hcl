locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  org_config_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org_name        = local.org_config_vars.locals.infras_organization

  # vault_config_vars       = read_terragrunt_config(find_in_parent_folders("vault-config.hcl"))
  # vault_address           = local.vault_config_vars.locals.address
  # vault_token             = local.vault_config_vars.locals.token
  # vault_token_secret_name = "vault-token"

  # secret_store_name = "vault-backend"
  # secrets          = local.environment_vars.locals.secrets
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/${local.org_name}/k3s-resources"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/${local.org_name}/k3s-resources?ref=${local.environment}"
}

include {
  path = find_in_parent_folders("root.hcl")
}

# ArgoCD reads GitHub/ArgoCD creds from vault-secrets and the ESO SecretStore name from
# external-secrets. mock_outputs let the FIRST bring-up pass plan (ArgoCD off) before those
# stacks exist; the SECOND pass (ArgoCD on) uses their real, applied outputs. Apply order:
#   k3s-resources (argocd_conf absent) → vault-secrets → external-secrets → k3s-resources (this).
dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    secrets = {
      "github/params" = { url = "https://github.com/MOCK", gitops_repo = "gitops-apps" }
      "github/creds"  = { ssh_priv_key = "MOCK" }
      "argocd/creds"  = { password = "MOCK" }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "external-secrets" {
  config_path = "../external-secrets"
  mock_outputs = {
    gitops_backend_name = "gitops-backend"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
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

    # Traefik's OWN route: the dashboard (api@internal isn't a k8s Service → IngressRoute, not
    # HTTPRoute). Reachable at http://traefik.k3s.local once mapped in /etc/hosts.
    routing = {
      dashboard_routes = [
        {
          name      = "traefik-dashboard"
          namespace = "traefik"
          host      = "traefik.k3s.local"
        },
      ]
    }
  }

  # Routing controller for Gateway API routes (future services). Per-app routes live in each
  # app's own `routing` block; Vault has none (it's on an Ingress, not Gateway API).
  route_type = "traefik"

  # Controller + CRDs only (self-signed issuers) — deploys BEFORE vault so its
  # Certificate/Issuer manifests have the CRDs available. No ACME/Cloudflare here.
  cert_manager_conf = {
    helm = {
      chart_version = "1.16.1"
      namespace     = "cert-manager"
      repository    = "https://charts.jetstack.io"
      release_name  = "cert-manager"
      values_type   = "controller"
    }

    common = {
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
      sc_name               = "vault-sc"         # StorageClass created by sc.yml.tftpl
      vault_service_name    = "vault"            # MUST equal helm.release_name (retry_join + cert SANs)
      vault_tls_server_name = "vault-tls-server" # cert-manager server-cert secret (mounted)
      vault_tls_ca_name     = "vault-tls-ca"     # cert-manager CA secret
      host                  = "vault.k3s.local"  # Traefik ingress host + cert SAN
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
      domain = "argocd.k3s.${local.environment}"
    }

    # Names for the chart's ExternalSecrets (applied after the release; reconcile once the gitops
    # SecretStore exists). store_name = the ESO SecretStore in the gitops ns (external-secrets stack).
    secret = {
      store_name                = dependency.external-secrets.outputs.gitops_backend_name
      argocd_secret_name        = "argocd-ex-secret"
      docker_config_secret_name = "docker-ex-configjson"
      docker_token_secret_name  = "docker-ex-token"
      github_secret_name        = "github-ex-ssh-priv-key"
    }

    github = {
      url          = dependency.vault-secrets.outputs.secrets["github/params"]["url"]
      gitops_repo  = dependency.vault-secrets.outputs.secrets["github/params"]["gitops_repo"]
      ssh_priv_key = dependency.vault-secrets.outputs.secrets["github/creds"]["ssh_priv_key"]
    }

    common = {
      admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password"]
    }

    # UI/API via Gateway API HTTPRoute on the shared traefik-gateway `web` listener. HTTPRoute
    # lives in `gitops` (same ns as the backend Service → no ReferenceGrant); parentRef crosses
    # into `traefik` (allowed, listener is from:All). backend_name = the argocd-server Service:
    # VERIFY with `kubectl get svc -n gitops` after install (chart fullname logic → expected
    # `argo-cd-server`; adjust here if the chart names it `argo-cd-argocd-server`).
    routing = {
      httproutes = [
        {
          name              = "argocd"
          namespace         = "gitops"
          gateway_name      = "traefik-gateway"
          gateway_namespace = "traefik"
          section_name      = "web"
          hostnames         = ["argocd.k3s.${local.environment}"]
          path_prefix       = "/"
          backend_name      = "argo-cd-server"
          backend_port      = 80
        }
      ]
    }
  }
  #
  # argocd_img_upd_conf = {
  #   helm = {
  #     chart_version = "0.12.0"
  #     namespace     = "gitops"
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
  # reloader_conf = {
  #   helm = {
  #     chart_version = "2.0.0"
  #     namespace     = "kube-system"
  #     repository    = "https://stakater.github.io/stakater-charts"
  #     release_name  = "reloader"
  #   }
  #
  #   common = {
  #     rq_mem       = "128Mi"
  #     rq_cpu       = "10m"
  #     limits_mem   = "512Mi"
  #     limits_cpu   = "100m"
  #     storage_size = "10Gi"
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
  # vault_conf = {
  #   helm = {
  #     chart_version = "0.28.1"
  #     namespace     = "vault"
  #     repository    = "https://helm.releases.hashicorp.com"
  #     release_name  = "vault"
  #   }
  #
  #   server = {
  #     rq_mem     = "512Mi"
  #     rq_cpu     = "250m"
  #     limits_mem = "1Gi"
  #     limits_cpu = "500m"
  #
  #     datastore_size       = "10Gi"
  #     datastore_mount_path = "/vault/datastore"
  #
  #     auditstore_size       = "10Gi"
  #     auditstore_mount_path = "/vault/auditstore"
  #   }
  #
  #   ui = {
  #     enabled = true
  #   }
  #
  #   injector = {
  #     rq_mem     = "256Mi"
  #     rq_cpu     = "250m"
  #     limits_mem = "512Mi"
  #     limits_cpu = "500m"
  #   }
  #
  #   common = {
  #     consul_server_url = "consul-server:8500"
  #     sc_name           = "vault-sc"
  #
  #     external_vault_addr   = "vault-server:8200"
  #     vault_server_url      = get_env("VAULT_ADDR", "")
  #     vault_server_token    = get_env("VAULT_TOKEN", "")
  #     vault_tls_server_name = "vault-tls-server"
  #     vault_tls_ca_name     = "vault-tls-ca"
  #     host                  = "vault.k3s.local"
  #     rootpath              = "/"
  #   }
  # }

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
