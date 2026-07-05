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

inputs = {
  coredns_conf = {
    helm = {
      chart_version = "1.10.101-build2021022303"
      namespace     = "kube-system"
      repository    = "https://rke2-charts.rancher.io/"
      release_name  = "rke2-coredns"
    }

    common = {
    }
  }

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
  }

  # argocd_conf = {
  #   helm = {
  #     chart_version = "7.8.10"
  #     namespace     = "gitops"
  #     repository    = "https://argoproj.github.io/argo-helm"
  #     release_name  = "argo-cd"
  #   }
  #
  #   ingress = {
  #     baseref         = "/"
  #     rootpath        = "/"
  #     midl_prefix     = "/"
  #     ingroute_prefix = "/"
  #     domain          = "argocd.k3s.${local.environment}"
  #   }
  #
  #   secret = {
  #     vault_token_secret_name   = local.vault_token_secret_name
  #     store_name                = dependency.external-secrets.outputs.gitops_backend_name
  #     argocd_secret_name        = "argocd-ex-secret"
  #     docker_config_secret_name = "docker-ex-configjson"
  #     docker_token_secret_name  = "docker-ex-token"
  #     github_secret_name        = "github-ex-ssh-priv-key"
  #     vault_address             = local.vault_address
  #     vault_token               = base64encode(local.vault_token)
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
  # }
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
