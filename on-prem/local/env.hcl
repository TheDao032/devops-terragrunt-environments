# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault-config.hcl"))
  vault_address     = local.vault_config_vars.locals.address
  vault_token       = local.vault_config_vars.locals.token

  environment        = "local"
  external_server_ip = get_env("K3S_SERVER_1")

  secrets = {
    "artifactory/params" = {
      registry = get_env("ARTIFACTORY_REGISTRY", "nthedao")
    }

    # Only for k3d local kubernetes cluster
    # "k3s/creds" = {
    #   client_ca_crt = get_env("KUBE_CLUSTER_CA_CERT_DATA")
    #   host          = get_env("KUBE_HOST")
    #   client_crt    = get_env("KUBE_CLIENT_CERT_DATA")
    #   client_key    = get_env("KUBE_CLIENT_KEY_DATA")
    #   token         = get_env("KUBE_TOKEN")
    # }

    # server-2                = get_env("K3S_SERVER_2")
    # agent-2                 = get_env("K3S_AGENT_2")
    "k3s/params" = {
      server-1                = get_env("K3S_SERVER_1")
      agent-1                 = get_env("K3S_AGENT_1")
      api_endpoint            = get_env("K3S_SERVER_1")
      keepalived_virtual_ip   = get_env("KEEPALIVED_VIRTUAL_IP")
      keepalived_nw_interface = get_env("KEEPALIVED_NW_INTERFACE")
      load_balancer_port      = get_env("LOAD_BALANCER_PORT")
      psql_version            = get_env("PSQL_VERSION")
      k3s_server_cidr_range   = get_env("K3S_SERVER_CIDR_RANGE")
      k3s_version             = get_env("K3S_VERSION")
      extra_server_args       = ""
      extra_agent_args        = ""
    }

    "ldap/params" = {
      serverUrl = get_env("LDAP_SERVER_URL", "http://192.168.1.146:389")
    }
    "ldap/creds" = {
      providerBindCredential    = get_env("LDAP_PROVIDER_BIND_CREDENTIAL", "admin_pass")
      providerBindDN            = get_env("LDAP_PROVIDER_BIND_DN", "cn=admin,dc=nthedao,dc=info")
      providerUsersDN           = get_env("LDAP_PROVIDER_USERS_DN", "cn=dev,ou=users,dc=nthedao,dc=info")
      providerUserObjectClasses = get_env("LDAP_PROVIDER_USER_OBJECT_CLASSES", "inetOrgPerson,posixAccount,top,organizationalPerson,person")
    }

    "keycloak/params" = {
    }
    "keycloak/creds" = {
      username = "admin"
      password = "{ _RANDOM_ = 18 }"
    }

    "keycloak/kafkaUI/creds" = {
      clientID     = "kafka-ui"
      clientName   = "kafka-ui"
      clientPrefix = "/kafka-ui"
      clientSecret = "{ _RANDOM_ = 32 }"
    }

    "keycloak/queryService/creds" = {
      clientID     = "query-service"
      clientName   = "query-service"
      clientPrefix = "/query"
      clientSecret = "{ _RANDOM_ = 32 }"
    }

    "jenkins/creds" = {
      username = "admin"
      password = "{ _RANDOM_ = 18 }"
    }

    "grafana/creds" = {
      username = "admin"
      password = "{ _RANDOM_ = 18 }"
    }

    "kafka/creds" = {
      clientUsername = "admin"
      clientPassword = "{ _RANDOM_ = 18 }"
    }

    "vault/params" = {
      clusterAddr = local.vault_address
    }

    "vault/creds" = {
      rootToken = local.vault_token
    }

    "Database/params" = {
      DBClusterEndpoint = get_env("DB_CLUSTER_ENDPOINT", "192.168.56.31")
      DBClusterPort     = 5432
      agileUrl          = get_env("AGILE_DB_URL")
      agilePort         = get_env("AGILE_DB_PORT")
      agileCorpUrl      = get_env("CORP_AGILE_DB_URL")
      agileCorpPort     = get_env("CORP_AGILE_DB_PORT")
    }

    "Database/fiesta/creds" = {
      username = "fiesta"
      password = "{ _RANDOM_ = 18 }"
      database = "fiesta"
    }

    "Database/keycloak/creds" = {
      pgPassword = "{ _RANDOM_ = 18 }"
      password   = "{ _RANDOM_ = 18 }"
      username   = "bn_keycloak"
      database   = "keycloak"
    }

    "Database/agile/creds" = {
      username = get_env("AGILE_DB_USERNAME")
      password = get_env("AGILE_DB_PASSWORD")
      sid      = get_env("AGILE_DB_SID")

      corpUsername = get_env("CORP_AGILE_DB_USERNAME")
      corpPassword = get_env("CORP_AGILE_DB_PASSWORD")
      corpSid      = get_env("CORP_AGILE_DB_SID")

      jdbcConnectionString     = get_env("AGILE_DB_JDBC_CONNECTION_STRING")
      corpJDBCConnectionString = get_env("CORP_AGILE_DB_JDBC_CONNECTION_STRING")
    }

    "agile/app/params" = {
      port = get_env("AGILE_APP_PORT")
      url  = get_env("AGILE_APP_URL")
    }

    "agile/app/creds" = {
      username = get_env("AGILE_APP_USERNAME")
      password = get_env("AGILE_APP_PASSWORD")
    }

    "hikari/params" = {
      maximumPoolSize   = get_env("HIKARI_MAXIMUM_POOL_SIZE")
      minimumIdle       = get_env("HIKARI_MINIMUM_IDLE")
      connectionTimeout = get_env("HIKARI_CONNECTION_TIMEOUT")
      maxLifeTime       = get_env("HIKARI_MAX_LIFE_TIME")
      poolName          = get_env("HIKARI_POOL_NAME")
    }

    "authHeader/creds" = {
      key   = get_env("AUTHOR_KEY")
      value = get_env("AUTHOR_VALUE")
    }

    "queryService/params" = {
      queryServicePort              = get_env("QUERY_SERVICE_PORT")
      queryServiceName              = get_env("QUERY_SERVICE_NAME")
      queryServiceTimeInterval      = get_env("QUERY_SERVICE_TIME_INTERVAL")
      queryServiceOpnLegacyOrg      = get_env("QUERY_SERVICE_OPN_LEGACY_ORG")
      queryServiceMaterialLegacyOrg = get_env("QUERY_SERVICE_MATERIAL_LEGACY_ORG")
      javaOpsXms                    = get_env("JAVA_OPS_XMS")
    }
  }

  cloudflare_api_token = get_env("CLOUDFLARE_API_TOKEN", "")

  keycloak_client_information = {
    default_client_scopes = [
      "web-origins",
      "acr",
      "profile",
      "roles",
      "basic",
      "email"
    ]

    optional_client_scopes = [
      "address",
      "phone",
      "organization",
      "offline_access",
      "microprofile-jwt"
    ]
  }

  tags = {
    CreatedBy = "Terraform"
  }

  # default_service_secrets = {
  #   "agile/app/params" = {
  #     port = get_env("AGILE_APP_PORT")
  #     url  = get_env("AGILE_APP_URL")
  #   }
  #   "agile/app/creds" = {
  #     username = get_env("AGILE_APP_USERNAME")
  #     password = get_env("AGILE_APP_PASSWORD")
  #   }
  #
  #   "hikari/params" = {
  #     maximumPoolSize   = get_env("HIKARI_MAXIMUM_POOL_SIZE")
  #     minimumIdle       = get_env("HIKARI_MINIMUM_IDLE")
  #     connectionTimeout = get_env("HIKARI_CONNECTION_TIMEOUT")
  #     maxLifeTime       = get_env("HIKARI_MAX_LIFE_TIME")
  #     poolName          = get_env("HIKARI_POOL_NAME")
  #   }
  #
  #   "authHeader/creds" = {
  #     key   = get_env("AUTHOR_KEY")
  #     value = get_env("AUTHOR_VALUE")
  #   }
  # }
  #
  # query_service = {
  #   "queryService/params" = {
  #     queryServicePort              = get_env("QUERY_SERVICE_PORT")
  #     queryServiceName              = get_env("QUERY_SERVICE_NAME")
  #     queryServiceTimeInterval      = get_env("QUERY_SERVICE_TIME_INTERVAL")
  #     queryServiceOpnLegacyOrg      = get_env("QUERY_SERVICE_OPN_LEGACY_ORG")
  #     queryServiceMaterialLegacyOrg = get_env("QUERY_SERVICE_MATERIAL_LEGACY_ORG")
  #     javaOpsXms                    = get_env("JAVA_OPS_XMS")
  #   }
  # }
  #
  # k3s = {
  #   "k3s/params" = {
  #     server-1                = get_env("K3S_SERVER_1")
  #     server-2                = get_env("K3S_SERVER_2")
  #     agent-1                 = get_env("K3S_AGENT_1")
  #     agent-2                 = get_env("K3S_AGENT_2")
  #     api_endpoint            = get_env("K3S_SERVER_1")
  #     keepalived_virtual_ip   = get_env("KEEPALIVED_VIRTUAL_IP")
  #     keepalived_nw_interface = get_env("KEEPALIVED_NW_INTERFACE")
  #     load_balancer_port      = get_env("LOAD_BALANCER_PORT")
  #     psql_version            = get_env("PSQL_VERSION")
  #     k3s_server_cidr_range   = get_env("K3S_SERVER_CIDR_RANGE")
  #     k3s_version             = get_env("K3S_VERSION")
  #     extra_server_args       = ""
  #     extra_agent_args        = ""
  #   }
  # }
  #
  # ldap = {
  #   "ldap/params" = {
  #     serverUrl = get_env("LDAP_SERVER_URL", "http://192.168.1.146:389")
  #   }
  #   "ldap/creds" = {
  #     providerBindCredential    = get_env("LDAP_PROVIDER_BIND_CREDENTIAL", "admin_pass")
  #     providerBindDN            = get_env("LDAP_PROVIDER_BIND_DN", "cn=admin,dc=nthedao,dc=info")
  #     providerUsersDN           = get_env("LDAP_PROVIDER_USERS_DN", "cn=dev,ou=users,dc=nthedao,dc=info")
  #     providerUserObjectClasses = get_env("LDAP_PROVIDER_USER_OBJECT_CLASSES", "inetOrgPerson,posixAccount,top,organizationalPerson,person")
  #   }
  # }
  #
  # keycloak = {
  #   "keycloak/params" = {
  #   }
  #   "keycloak/creds" = {
  #     username = "admin"
  #     password = "{ _RANDOM_ = 18 }"
  #   }
  #
  #   "keycloak/kafkaUI/creds" = {
  #     clientID     = "kafka-ui"
  #     clientName   = "kafka-ui"
  #     clientPrefix = "/kafka-ui"
  #     clientSecret = "{ _RANDOM_ = 32 }"
  #   }
  #
  #   "keycloak/queryService/creds" = {
  #     clientID     = "query-service"
  #     clientName   = "query-service"
  #     clientPrefix = "/query"
  #     clientSecret = "{ _RANDOM_ = 32 }"
  #   }
  # }
  #
  # jenkins = {
  #   "jenkins/creds" = {
  #     username = "admin"
  #     password = "{ _RANDOM_ = 18 }"
  #   }
  # }
  #
  # grafana = {
  #   "grafana/creds" = {
  #     username = "admin"
  #     password = "{ _RANDOM_ = 18 }"
  #   }
  # }
  #
  # kafka = {
  #   "kafka/creds" = {
  #     clientUsername = "admin"
  #     clientPassword = "{ _RANDOM_ = 18 }"
  #   }
  # }
  #
  # vault = {
  #   "vault/params" = {
  #     clusterAddr = local.vault_address
  #   }
  #
  #   "vault/creds" = {
  #     rootToken = local.vault_token
  #   }
  # }
  #
  # database = {
  #   "Database/params" = {
  #     DBClusterEndpoint = get_env("DB_CLUSTER_ENDPOINT", "192.168.56.31")
  #     DBClusterPort     = 5432
  #     agileUrl          = get_env("AGILE_DB_URL")
  #     agilePort         = get_env("AGILE_DB_PORT")
  #     agileCorpUrl      = get_env("CORP_AGILE_DB_URL")
  #     agileCorpPort     = get_env("CORP_AGILE_DB_PORT")
  #   }
  #
  #   "Database/fiesta/creds" = {
  #     username = "fiesta"
  #     password = "{ _RANDOM_ = 18 }"
  #     database = "fiesta"
  #   }
  #
  #   "Database/keycloak/creds" = {
  #     pgPassword = "{ _RANDOM_ = 18 }"
  #     password   = "{ _RANDOM_ = 18 }"
  #     username   = "bn_keycloak"
  #     database   = "keycloak"
  #   }
  #
  #   "Database/agile/creds" = {
  #     username = get_env("AGILE_DB_USERNAME")
  #     password = get_env("AGILE_DB_PASSWORD")
  #     sid      = get_env("AGILE_DB_SID")
  #
  #     corpUsername = get_env("CORP_AGILE_DB_USERNAME")
  #     corpPassword = get_env("CORP_AGILE_DB_PASSWORD")
  #     corpSid      = get_env("CORP_AGILE_DB_SID")
  #
  #     jdbcConnectionString     = get_env("AGILE_DB_JDBC_CONNECTION_STRING")
  #     corpJDBCConnectionString = get_env("CORP_AGILE_DB_JDBC_CONNECTION_STRING")
  #   }
  #
  # }

  # global = {
  #   "artifactory/params" = {
  #     registry = get_env("ARTIFACTORY_REGISTRY", "nthedao")
  #   }
  # }

  # psql_vms = {
  #   conn-pool: get_env("PSQL_CONN_POOL")
  #   coordinator1: get_env("PSQL_COORDINATOR_1")
  #   worker1: get_env("PSQL_WORKER_1")
  #   worker2: get_env("PSQL_WORKER_2")
  # }
}
