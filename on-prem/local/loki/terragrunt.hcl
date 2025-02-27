locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  # secrets          = local.environment_vars.locals.secrets
}

terraform {
  source = "../../../../terraform-modules//on-prem/loki"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/kafka?ref=${local.environment}"
}

# dependency "vault-secrets" {
#   config_path = "../vault-secrets"
#   mock_outputs = {
#     kafka_secrets = {
#       "kafka/creds" = {
#         clientUsername = "value"
#         clientPassword = "value"
#       }
#     }
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }

# dependency "prometheus" {
#   config_path = "../prometheus"
#   mock_outputs = {
#     kafka_secrets = {
#       clientPassword = "value"
#     }
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }

include {
  path = find_in_parent_folders()
}

inputs = {
  helm_repository = "https://grafana.github.io/helm-charts"
  namespace       = "monitoring"

  loki_chart_version      = "6.23.0"
  loki_helm_release_name  = "loki"
  loki_helm_release_chart = "loki"

  alloy_chart_version      = "0.10.0"
  alloy_helm_release_name  = "alloy"
  alloy_helm_release_chart = "alloy"

  common_conf = {
    ingress = {
      host         = "loki.nthedao.info"
      prefix       = "/loki"
      prefix_type  = "Prefix"
      strip_prefix = "loki-strip-prefix"
    }
  }

  microservice_conf = {
    storage = {
      type = "filesystem"
    }

    ingester = {
      replicas = 1
    }
    querier = {
      replicas        = 1
      max_concurrent  = 4
      max_unavailable = 1
    }
    query_frontend = {
      replicas        = 1
      max_unavailable = 1
    }
    query_scheduler = {
      replicas = 1
    }
    distributor = {
      replicas        = 1
      max_unavailable = 1
    }
    compactor = {
      replicas = 1
    }
    index_gateway = {
      replicas        = 1
      max_unavailable = 1
    }

    bloom_planner = {
      replicas = 0
    }
    bloom_builder = {
      replicas = 0
    }
    bloom_gateway = {
      replicas = 0
    }

    write = {
      replicas = 0
    }
    read = {
      replicas = 0
    }
    backend = {
      replicas = 0
    }

    single_inary = {
      replicas = 0
    }

    # ruler = {
    #   replicas       = 1
    #   max_unavailable = 1
    #   storage = {
    #     type = "filesystem"
    #   }
    # }

    memcached = {
      rq_mem     = "128Mi"
      rq_cpu     = "250m"
      limits_mem = "512Mi"
      limits_cpu = "500m"
    }

    memcached_exporter = {
      rq_mem     = "128Mi"
      rq_cpu     = "250m"
      limits_mem = "512Mi"
      limits_cpu = "500m"
    }
  }

  monolithic_conf = {
    storage = {
      type = "filesystem"
    }

    singleBinary = {
      replicas = 0
    }

    memcached = {
      rq_mem     = "128Mi"
      rq_cpu     = "250m"
      limits_mem = "512Mi"
      limits_cpu = "500m"
    }

    memcached_exporter = {
      rq_mem     = "128Mi"
      rq_cpu     = "250m"
      limits_mem = "512Mi"
      limits_cpu = "500m"
    }
  }

  scalable_conf = {
    querier = {
      max_concurrent = 2
    }
    write = {
      replicas        = 1
      persistent_size = "10Gi"
    }
    read = {
      replicas        = 1
      persistent_size = "10Gi"
    }
    backend = {
      replicas        = 2
      persistent_size = "10Gi"
    }

    memcached = {
      rq_mem     = "128Mi"
      rq_cpu     = "250m"
      limits_mem = "512Mi"
      limits_cpu = "500m"
    }

    memcached_exporter = {
      rq_mem     = "128Mi"
      rq_cpu     = "250m"
      limits_mem = "512Mi"
      limits_cpu = "500m"
    }
  }

  alloy_conf = {
    controller = {
      auto_scale = {
        min_replicas = 1
        max_replicas = 2
      }
    }
  }
}
