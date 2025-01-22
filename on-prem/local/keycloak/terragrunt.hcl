locals {
  environment_vars            = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment                 = local.environment_vars.locals.environment
  keycloak_client_information = local.environment_vars.locals.keycloak_client_information
  tags                        = local.environment_vars.locals.tags
  external_server_ip          = local.environment_vars.locals.external_server_ip
  kafka_ui_url                = "http://${local.external_server_ip}/kafka-ui"
  keycloak_uri                = "http://${local.external_server_ip}/keycloak"
}

terraform {
  source = "../../../../terraform-modules//on-prem/keycloak"
}

dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    secrets = {
      "keycloak/creds" = {
        username = "value"
        password = "value"
      }
      "keycloak/kafkaUI/creds" = {
        clientID     = "value"
        clientName   = "value"
        clientSecret = "value"
      }

      "ldap/params" = {
        serverUrl = "value"
      }

      "ldap/creds" = {
        providerBindCredential    = "value"
        providerBindDN            = "value"
        providerUsersDN           = "value"
        providerUserObjectClasses = "value"
      }

      "Database/keycloak/creds" = {
        pgPassword = "value"
        username   = "value"
        password   = "value"
        database   = "value"
      }
    }
    # keycloak_secrets = {
    #   "keycloak/creds" = {
    #     username = "value"
    #     password = "value"
    #   }
    #   "keycloak/kafkaUI/creds" = {
    #     clientID     = "value"
    #     clientName   = "value"
    #     clientSecret = "value"
    #   }
    # }

    # ldap_secrets = {
    #   "ldap/params" = {
    #     serverUrl = "value"
    #   }
    #   "ldap/creds" = {
    #     providerBindCredential    = "value"
    #     providerBindDN            = "value"
    #     providerUsersDN           = "value"
    #     providerUserObjectClasses = "value"
    #   }
    # }

    # database_secrets = {
    #   "Database/keycloak/creds" = {
    #     pgPassword = "value"
    #     username   = "value"
    #     password   = "value"
    #     database   = "value"
    #   }
    # }

    vault_mount_path = "value"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  chart_version      = "24.2.0"
  namespace          = "tools"
  helm_repository    = "https://charts.bitnami.com/bitnami"
  helm_release_name  = "keycloak"
  helm_release_chart = "keycloak"
  vault_mount_path   = dependency.vault-secrets.outputs.vault_mount_path
  tags               = local.tags

  keycloak_host          = local.external_server_ip
  keycloak_params        = dependency.vault-secrets.outputs.secrets["keycloak/params"]
  keycloak_kafkaui_creds = dependency.vault-secrets.outputs.secrets["keycloak/kafkaUI/creds"]
  keycloak_conf = {
    storage = {
      class_name = "keycloak-sc"
    }

    ingress = {
      host         = "kafkaui.nthedao.info"
      prefix       = "/keycloak"
      prefix_type  = "Prefix"
      strip_prefix = "keycloak-strip-prefix"
    }

    admin_ingress = {
      host         = "admin.kafkaui.nthedao.info"
      prefix       = "/keycloak-admin"
      prefix_type  = "Prefix"
      strip_prefix = "keycloak-admin-strip-prefix"
    }

    resources = {
      rq_mem     = "512Mi"
      rq_cpu     = "2"
      limits_mem = "1024Mi"
      limits_cpu = "3"
    }

    database = {
      pg_password = dependency.vault-secrets.outputs.secrets["Database/keycloak/creds"]["pgPassword"]
      username    = dependency.vault-secrets.outputs.secrets["Database/keycloak/creds"]["username"]
      password    = dependency.vault-secrets.outputs.secrets["Database/keycloak/creds"]["password"]
      database    = dependency.vault-secrets.outputs.secrets["Database/keycloak/creds"]["database"]
    }

    auth = {
      admin_username = dependency.vault-secrets.outputs.secrets["keycloak/creds"]["username"]
      admin_password = dependency.vault-secrets.outputs.secrets["keycloak/creds"]["password"]
    }
  }

  realm = {
    name = local.environment
  }

  clients = {
    kafka_ui = merge(
      {
        prefix             = dependency.vault-secrets.outputs.secrets["keycloak/kafkaUI/creds"]["clientPrefix"]
        enabled            = "true"
        id                 = dependency.vault-secrets.outputs.secrets["keycloak/kafkaUI/creds"]["clientID"]
        name               = dependency.vault-secrets.outputs.secrets["keycloak/kafkaUI/creds"]["clientName"]
        root_url           = local.kafka_ui_url
        admin_url          = local.kafka_ui_url
        base_url           = local.kafka_ui_url
        is_alw_display     = "true"
        authenticator_type = "client-secret"
        secret             = dependency.vault-secrets.outputs.secrets["keycloak/kafkaUI/creds"]["clientSecret"]
        redirect_uris = [
          local.kafka_ui_url,
          "${local.kafka_ui_url}/*"
        ]
        web_origins = ["*"]
        protocol    = "openid-connect"
        attributes = {
          login_theme                               = "keycloak.v2"
          post_logout_redirect_uris                 = "${local.keycloak_uri}/realms/${local.environment}/protocol/openid-connect/logout"
          frontchannel_logout_url                   = "${local.keycloak_uri}/realms/${local.environment}/protocol/openid-connect/logout"
          oauth2_device_authorization_grant_enabled = "true"
        }
      },
      local.keycloak_client_information
    )
    query_service = merge(
      {
        prefix             = dependency.vault-secrets.outputs.secrets["keycloak/queryService/creds"]["clientPrefix"]
        enabled            = "true"
        id                 = dependency.vault-secrets.outputs.secrets["keycloak/queryService/creds"]["clientID"]
        name               = dependency.vault-secrets.outputs.secrets["keycloak/queryService/creds"]["clientName"]
        root_url           = local.kafka_ui_url
        admin_url          = local.kafka_ui_url
        base_url           = local.kafka_ui_url
        is_alw_display     = "true"
        authenticator_type = "client-secret"
        secret             = dependency.vault-secrets.outputs.secrets["keycloak/queryService/creds"]["clientSecret"]
        redirect_uris = [
          local.kafka_ui_url,
          "${local.kafka_ui_url}/*"
        ]
        web_origins = ["*"]
        protocol    = "openid-connect"
        attributes = {
          login_theme                               = "keycloak.v2"
          post_logout_redirect_uris                 = "${local.keycloak_uri}/realms/${local.environment}/protocol/openid-connect/logout"
          frontchannel_logout_url                   = "${local.keycloak_uri}/realms/${local.environment}/protocol/openid-connect/logout"
          oauth2_device_authorization_grant_enabled = "true"
        }
      },
      local.keycloak_client_information
    )
  }

  user_federations = {
    ldap = {
      name = "ldap"
      id   = "ldap"
      config = {
        priority                = ["0"]
        import_enabled          = ["true"]
        sync_registrations      = ["true"]
        vendor                  = ["ad"]
        username_ldap_attribute = ["cn"]
        rdn_ldap_attribute      = ["cn"]
        uuid_ldap_attribute     = ["entryUUID"]
        user_object_classes     = split(",", dependency.vault-secrets.outputs.secrets["ldap/creds"]["providerUserObjectClasses"])
        connection_url          = [dependency.vault-secrets.outputs.secrets["ldap/params"]["serverUrl"]]
        users_dn                = [dependency.vault-secrets.outputs.secrets["ldap/creds"]["providerUsersDN"]]
        auth_type               = ["simple"]
        bind_dn                 = [dependency.vault-secrets.outputs.secrets["ldap/creds"]["providerBindDN"]]
        bind_credential         = [dependency.vault-secrets.outputs.secrets["ldap/creds"]["providerBindCredential"]]
        search_scope            = ["2"]
        pagination              = ["true"]
        connection_pooling      = ["true"]
        cache_policy            = ["DEFAULT"]
        edit_mode               = ["WRITABLE"]
        full_sync_period        = ["86400"]
        changed_sync_period     = ["3600"]
      }
    }
  }
}
