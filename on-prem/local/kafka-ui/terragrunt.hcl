locals {
  environment_vars   = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment        = local.environment_vars.locals.environment
  external_server_ip = local.environment_vars.locals.external_server_ip
}

terraform {
  source = "../../../../terraform-modules//on-prem/kafka-ui"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/kafka?ref=${local.environment}"
}

dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    kafka_secrets = {
      "kafka/creds" = {
        clientUsername = "value"
        clientPassword = "value"
      }
    }
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "kafka" {
  config_path = "../kafka"
  mock_outputs = {
    internal_bootstrap_server = "value"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "keycloak" {
  config_path = "../keycloak"
  mock_outputs = {
    kafka_ui_credentials = {}
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}


include {
  path = find_in_parent_folders()
}

inputs = {
  image_tag                      = "latest"
  chart_version                  = "2024.6.4"
  namespace                      = "tools"
  helm_repository                = "https://charts.appscode.com/stable/"
  helm_release_name              = "kafka-ui"
  helm_release_chart             = "kafka-ui"
  kafka_ui_host                  = local.external_server_ip
  internal_bootstrap_server      = dependency.kafka.outputs.internal_bootstrap_server
  internal_bootstrap_server_port = 9092
  keycloak_kafka_ui_credentials  = dependency.keycloak.outputs.kafka_ui_credentials

  kafka_ui_conf = {
    ingress = {
      host         = "nthedao.info"
      prefix       = "/"
      prefix_type  = "Prefix"
      strip_prefix = "kafka-ui-strip-prefix"
    }

    sasl_conf = {
      client_username = dependency.vault-secrets.outputs.kafka_secrets["kafka/creds"]["clientUsername"]
      client_password = dependency.vault-secrets.outputs.kafka_secrets["kafka/creds"]["clientPassword"]
    }

    keycloak = {
      host          = dependency.keycloak.outputs.kafka_ui_credentials.keycloak_host
      client_id     = dependency.keycloak.outputs.kafka_ui_credentials.client_id
      client_name   = dependency.keycloak.outputs.kafka_ui_credentials.client_name
      client_secret = dependency.keycloak.outputs.kafka_ui_credentials.client_secret
    }
  }
}
