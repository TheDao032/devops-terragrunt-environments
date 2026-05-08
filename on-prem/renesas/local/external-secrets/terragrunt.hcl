locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault-config.hcl"))

  vault_config = {
    vault_address           = local.vault_config_vars.locals.address
    vault_token             = base64encode(local.vault_config_vars.locals.token)
    vault_token_secret_name = "vault-token"
  }


  # secret_store_name = "vault-backend"
  # secrets          = local.environment_vars.locals.secrets
}

terraform {
  # source = "../../../../../devops-terraform-modules//on-prem/external-secrets"
  source = "../../../../../devops-terraform-modules//on-prem/external-secrets"
}

# dependency "vault-secrets" {
#   config_path = "../vault-secrets"
#   mock_outputs = {
#     secrets = {
#       "github/params" = {
#         url         = "values"
#         gitops_repo = "values"
#       }
#
#       "github/creds" = {
#         ssh_priv_key = "values"
#       }
#     }
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }

include {
  path = find_in_parent_folders()
}

inputs = {
  local = {
    secret = merge(local.vault_config, {
      store_name = "local-backend"
    })

    common = {
      namespace = "local"
    }
  }

  gitops = {
    secret = merge(local.vault_config, {
      store_name = "gitops-backend"
    })

    common = {
      namespace = "gitops"
    }
  }

  #   argocd_conf = {
  #     helm = {
  #       chart_version = "7.8.10"
  #       namespace     = "gitops"
  #       repository    = "https://argoproj.github.io/argo-helm"
  #       release_name  = "argo-cd"
  #     }
  #
  #     ingress = {
  #       baseref         = "/"
  #       rootpath        = "/"
  #       midl_prefix     = "/"
  #       ingroute_prefix = "/"
  #       domain          = "argocd.k3s.local"
  #     }
  #
  #     secret = {
  #       vault_token_secret_name   = local.vault_token_secret_name
  #       store_name                = "argocd-store-backend"
  #       argocd_secret_name        = "argocd-ex-secret"
  #       docker_config_secret_name = "docker-ex-configjson"
  #       docker_token_secret_name  = "docker-ex-token"
  #       github_secret_name        = "github-ex-ssh-priv-key"
  #       vault_address             = local.vault_address
  #       vault_token               = base64encode(local.vault_token)
  #     }
  #
  #     github = {
  #       url          = dependency.vault-secrets.outputs.secrets["github/params"]["url"]
  #       gitops_repo  = dependency.vault-secrets.outputs.secrets["github/params"]["gitops_repo"]
  #       ssh_priv_key = dependency.vault-secrets.outputs.secrets["github/creds"]["ssh_priv_key"]
  #     }
  #
  #     common = {
  #       admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password"]
  #     }
  #   }
  #
  #   argocd_img_upd_conf = {
  #     helm = {
  #       chart_version = "0.12.0"
  #       namespace     = "gitops"
  #       repository    = "https://argoproj.github.io/argo-helm"
  #       release_name  = "argocd-image-updater"
  #     }
  #
  #     docker = {
  #       secret_name  = "docker-ex-token"
  #       organization = dependency.vault-secrets.outputs.secrets["docker/creds"]["username"]
  #     }
  #
  #     common = {
  #       admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password"]
  #     }
  #   }
  #
  #   jenkins_conf = {
  #     helm = {
  #       chart_version = "5.7.3"
  #       image_tag     = "2.479-jdk17"
  #       namespace     = "gitops"
  #       repository    = "https://charts.jenkins.io/"
  #       release_name  = "jenkins"
  #     }
  #
  #     common = {
  #       hostname    = "traefik.jenkins.local.com"
  #       url         = "http://traefik.jenkins.local.com/"
  #       sc_name     = "jenkins-sc"
  #       volume_size = "30Gi"
  #       username    = dependency.vault-secrets.outputs.secrets["jenkins/creds"]["username"]
  #       password    = dependency.vault-secrets.outputs.secrets["jenkins/creds"]["password"]
  #     }
  #
  #     plugins = {
  #       kubernetes                             = "4295.v7fa_01b_309c95"
  #       workflow-aggregator                    = "600.vb_57cdd26fdd7"
  #       git                                    = "5.5.2"
  #       github                                 = "1.40.0"
  #       configuration-as-code                  = "1850.va_a_8c31d3158b_"
  #       blueocean-bitbucket-pipeline           = "1.27.16"
  #       bitbucket-push-and-pull-request        = "3.1.1"
  #       atlassian-bitbucket-server-integration = "4.1.0"
  #       parameterized-scheduler                = "277.v61a_4b_a_49a_c5c"
  #       github-checks                          = "589.v845136f916cd"
  #       thinBackup                             = "2.1.1"
  #       git-parameter                          = "0.9.19"
  #       hashicorp-vault-plugin                 = "371.v884a_4dd60fb_6"
  #     }
  #   }
  #
  #   coredns_conf = {
  #     helm = {
  #       chart_version = "1.10.101-build2021022303"
  #       namespace     = "kube-system"
  #       repository    = "https://rke2-charts.rancher.io/"
  #       release_name  = "rke2-coredns"
  #     }
  #
  #     common = {
  #     }
  #   }
  #
  #   kafka_conf = {
  #     helm = {
  #       chart_version = "31.0.0"
  #       image_tag     = "3.9.0-debian-12-r1"
  #       namespace     = "tools"
  #       repository    = "https://charts.bitnami.com/bitnami"
  #       release_name  = "kafka"
  #     }
  #
  #     controller = {
  #       replica_count = 1
  #       hpa_active    = true
  #       mount_path    = "/bitnami/kafka/controller"
  #       size          = "8Gi"
  #       min_replicas  = 1
  #       max_replicas  = 5
  #     }
  #
  #     broker = {
  #       replica_count = 1
  #       hpa_active    = true
  #       mount_path    = "/bitnami/kafka/broker"
  #       size          = "8Gi"
  #       min_replicas  = 1
  #       max_replicas  = 5
  #     }
  #
  #     sasl = {
  #       client_username : dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientUsername"]
  #       client_password : dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientPassword"]
  #     }
  #
  #     common = {
  #     }
  #   }
  #
  #   consul_conf = {
  #     helm = {
  #       chart_version = "1.5.3"
  #       namespace     = "vault"
  #       repository    = "https://helm.releases.hashicorp.com"
  #       release_name  = "consul"
  #     }
  #
  #     server = {
  #       rq_mem       = "200Mi"
  #       rq_cpu       = "100m"
  #       limits_mem   = "500Mi"
  #       limits_cpu   = "500m"
  #       storage_size = "10Gi"
  #     }
  #
  #     common = {
  #     }
  #   }
  #
  #   # consul_conf = {
  #   #   helm = {
  #   #     chart_version = "1.5.3"
  #   #     namespace     = "vault"
  #   #     repository    = "https://helm.releases.hashicorp.com"
  #   #     release_name  = "consul"
  #   #   }
  #   #
  #   #   vault = {
  #   #     rq_mem       = "200Mi"
  #   #     rq_cpu       = "100m"
  #   #     limits_mem   = "500Mi"
  #   #     limits_cpu   = "500m"
  #   #     storage_size = "10Gi"
  #   #   }
  #   #
  #   #   common = {
  #   #   }
  #   # }
  #
  #   vault_conf = {
  #     helm = {
  #       chart_version = "0.28.1"
  #       namespace     = "vault"
  #       repository    = "https://helm.releases.hashicorp.com"
  #       release_name  = "vault"
  #     }
  #
  #     server = {
  #       rq_mem     = "512Mi"
  #       rq_cpu     = "250m"
  #       limits_mem = "1Gi"
  #       limits_cpu = "500m"
  #
  #       datastore_size       = "10Gi"
  #       datastore_mount_path = "/vault/datastore"
  #
  #       auditstore_size       = "10Gi"
  #       auditstore_mount_path = "/vault/auditstore"
  #     }
  #
  #     ui = {
  #       enabled = true
  #     }
  #
  #     injector = {
  #       rq_mem     = "256Mi"
  #       rq_cpu     = "250m"
  #       limits_mem = "512Mi"
  #       limits_cpu = "500m"
  #     }
  #
  #     common = {
  #       consul_server_url = "consul-server:8500"
  #       sc_name           = "vault-sc"
  #
  #       external_vault_addr   = "vault-server:8200"
  #       vault_server_url      = "https://192.168.56.11:8200"
  #       vault_server_token    = get_env("VAULT_MASTER_TOKEN", "")
  #       vault_tls_server_name = "vault-tls-server"
  #       vault_tls_ca_name     = "vault-tls-ca"
  #       host                  = "vault.k3s.local"
  #       rootpath              = "/"
  #     }
  #   }

}
