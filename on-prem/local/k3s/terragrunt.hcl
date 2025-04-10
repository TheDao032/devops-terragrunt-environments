locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  vault_config_vars       = read_terragrunt_config(find_in_parent_folders("vault-config.hcl"))
  vault_address           = local.vault_config_vars.locals.address
  vault_token             = local.vault_config_vars.locals.token
  vault_token_secret_name = "vault-token"


  # secret_store_name = "vault-backend"
  # secrets          = local.environment_vars.locals.secrets
}

terraform {
  source = "../../../../terraform-modules//on-prem/k3s"
  # source = "git::git@github.com:TheDao032/demo-terraform-modules.git//amazon-web-service/eks?ref=${local.environment}"
}

dependency "external-secrets" {
  config_path = "../external-secrets"
  mock_outputs = {
    local_backend_name  = "values"
    gitops_backend_name = "values"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    secrets = {
      "jenkins/creds" = {
        username = "value"
        password = "value"
      }

      "argocd/creds" = {
        username = "value"
        password = "value"
      }

      "kafka/creds" = {
        clientUsername = "value"
        clientPassword = "value"
      }

      "github/params" = {
        url         = "values"
        gitops_repo = "values"
      }

      "vault/approle/${local.environment}/creds" = {
        client_token = "string",
        role_id      = "string",
        secret_id    = "string"
      }

      "vault/params" = {
        clusterAddr = "string"
      }

      "docker/creds" = {
        username = "string",
        password = "string",
        email    = "string"
      }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  external_secrets_conf = {
    helm = {
      chart_version = "0.15.0"
      namespace     = "kube-system"
      repository    = "https://charts.external-secrets.io/"
      release_name  = "external-secrets"
    }

    secret = {
      store_name              = "ex-secret-backend"
      vault_token_secret_name = local.vault_token_secret_name
      vault_address           = local.vault_address
      vault_token             = base64encode(local.vault_token)
    }

    common = {
    }
  }

  argocd_conf = {
    helm = {
      chart_version = "7.8.10"
      namespace     = "gitops"
      repository    = "https://argoproj.github.io/argo-helm"
      release_name  = "argo-cd"
    }

    ingress = {
      baseref         = "/"
      rootpath        = "/"
      midl_prefix     = "/"
      ingroute_prefix = "/"
      domain          = "argocd.k3s.${local.environment}"
    }

    secret = {
      vault_token_secret_name   = local.vault_token_secret_name
      store_name                = dependency.external-secrets.outputs.gitops_backend_name
      argocd_secret_name        = "argocd-ex-secret"
      docker_config_secret_name = "docker-ex-configjson"
      docker_token_secret_name  = "docker-ex-token"
      github_secret_name        = "github-ex-ssh-priv-key"
      vault_address             = local.vault_address
      vault_token               = base64encode(local.vault_token)
    }

    github = {
      url          = dependency.vault-secrets.outputs.secrets["github/params"]["url"]
      gitops_repo  = dependency.vault-secrets.outputs.secrets["github/params"]["gitops_repo"]
      ssh_priv_key = dependency.vault-secrets.outputs.secrets["github/creds"]["ssh_priv_key"]
    }

    common = {
      admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password"]
    }
  }

  argocd_img_upd_conf = {
    helm = {
      chart_version = "0.12.0"
      namespace     = "gitops"
      repository    = "https://argoproj.github.io/argo-helm"
      release_name  = "argocd-image-updater"
    }

    docker = {
      secret_name  = "docker-ex-token"
      organization = dependency.vault-secrets.outputs.secrets["docker/creds"]["username"]
    }

    common = {
      admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password"]
    }
  }

  reloader_conf = {
    helm = {
      chart_version = "2.0.0"
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

  jenkins_conf = {
    helm = {
      chart_version = "5.8.32"
      # image_tag     = "2.504-jdk17"
      namespace    = "default"
      repository   = "https://charts.jenkins.io/"
      release_name = "jenkins"
    }

    secrets = {
      vault_role_id   = dependency.vault-secrets.outputs.secrets["vault/approle/jenkins_app/creds"]["role_id"]
      vault_secret_id = dependency.vault-secrets.outputs.secrets["vault/approle/jenkins_app/creds"]["secret_id"]
      vault_token     = dependency.vault-secrets.outputs.secrets["vault/approle/jenkins_app/creds"]["client_token"]
      vault_url       = dependency.vault-secrets.outputs.secrets["vault/params"]["clusterAddr"]
      docker_token    = dependency.vault-secrets.outputs.secrets["docker/creds"]["password"]
    }

    common = {
      tag         = "2.504-jdk21"
      hostname    = "jenkins.k3s.${local.environment}"
      url         = "http://jenkins.k3s.${local.environment}/"
      sc_name     = "jenkins-sc"
      volume_size = "10Gi"
      username    = dependency.vault-secrets.outputs.secrets["jenkins/creds"]["username"]
      password    = dependency.vault-secrets.outputs.secrets["jenkins/creds"]["password"]
    }

    plugins = {
      kubernetes              = "4324.vfec199a_33512"
      workflow-aggregator     = "608.v67378e9d3db_1"
      git                     = "5.7.0"
      configuration-as-code   = "1932.v75cb_b_f1b_698d"
      github                  = "1.43.0"
      parameterized-scheduler = "285.ve611986d4c48"
      github-checks           = "602.v264a_83610da_6"
      thinBackup              = "2.1.1"
      git-parameter           = "435.va_f85861c663a_"
      hashicorp-vault-plugin  = "371.v884a_4dd60fb_6"
      docker-build-publish    = "1.4.0"
      # blueocean-bitbucket-pipeline           = "1.27.17"
      # bitbucket-push-and-pull-request        = "3.2.0"
      # atlassian-bitbucket-server-integration = "4.1.4"
    }
  }

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

  kafka_conf = {
    helm = {
      chart_version = "31.0.0"
      image_tag     = "3.9.0-debian-12-r1"
      namespace     = "tools"
      repository    = "https://charts.bitnami.com/bitnami"
      release_name  = "kafka"
    }

    controller = {
      replica_count = 1
      hpa_active    = true
      mount_path    = "/bitnami/kafka/controller"
      size          = "8Gi"
      min_replicas  = 1
      max_replicas  = 5
    }

    broker = {
      replica_count = 1
      hpa_active    = true
      mount_path    = "/bitnami/kafka/broker"
      size          = "8Gi"
      min_replicas  = 1
      max_replicas  = 5
    }

    sasl = {
      client_username : dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientUsername"]
      client_password : dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientPassword"]
    }

    common = {
    }
  }

  consul_conf = {
    helm = {
      chart_version = "1.5.3"
      namespace     = "vault"
      repository    = "https://helm.releases.hashicorp.com"
      release_name  = "consul"
    }

    server = {
      rq_mem       = "200Mi"
      rq_cpu       = "100m"
      limits_mem   = "500Mi"
      limits_cpu   = "500m"
      storage_size = "10Gi"
    }

    common = {
    }
  }

  # consul_conf = {
  #   helm = {
  #     chart_version = "1.5.3"
  #     namespace     = "vault"
  #     repository    = "https://helm.releases.hashicorp.com"
  #     release_name  = "consul"
  #   }
  #
  #   vault = {
  #     rq_mem       = "200Mi"
  #     rq_cpu       = "100m"
  #     limits_mem   = "500Mi"
  #     limits_cpu   = "500m"
  #     storage_size = "10Gi"
  #   }
  #
  #   common = {
  #   }
  # }

  vault_conf = {
    helm = {
      chart_version = "0.28.1"
      namespace     = "vault"
      repository    = "https://helm.releases.hashicorp.com"
      release_name  = "vault"
    }

    server = {
      rq_mem     = "512Mi"
      rq_cpu     = "250m"
      limits_mem = "1Gi"
      limits_cpu = "500m"

      datastore_size       = "10Gi"
      datastore_mount_path = "/vault/datastore"

      auditstore_size       = "10Gi"
      auditstore_mount_path = "/vault/auditstore"
    }

    ui = {
      enabled = true
    }

    injector = {
      rq_mem     = "256Mi"
      rq_cpu     = "250m"
      limits_mem = "512Mi"
      limits_cpu = "500m"
    }

    common = {
      consul_server_url = "consul-server:8500"
      sc_name           = "vault-sc"

      external_vault_addr   = "vault-server:8200"
      vault_server_url      = get_env("VAULT_ADDR", "")
      vault_server_token    = get_env("VAULT_TOKEN", "")
      vault_tls_server_name = "vault-tls-server"
      vault_tls_ca_name     = "vault-tls-ca"
      host                  = "vault.k3s.local"
      rootpath              = "/"
    }
  }

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
