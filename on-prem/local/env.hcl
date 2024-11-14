# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault-config.hcl"))
  vault_address     = local.vault_config_vars.locals.address
  vault_token       = local.vault_config_vars.locals.token

  environment = "local"

  k3s = {
    "k3s/params": {
      server-1: get_env("K3S_SERVER_1", "192.168.56.11")
      server-2: get_env("K3S_SERVER_2", "192.168.56.12")
      agent-1: get_env("K3S_AGENT_1", "192.168.56.21")
      agent-2: get_env("K3S_AGENT_2", "192.168.56.22")
      api_endpoint: get_env("K3S_SERVER_1", "192.168.56.11")
      keepalived_virtual_ip: get_env("KEEPALIVED_VIRTUAL_IP", "192.168.56.100")
      keepalived_nw_interface: get_env("KEEPALIVED_NW_INTERFACE", "eth1")
      load_balancer_port: get_env("LOAD_BALANCER_PORT", "6445")
      psql_version: get_env("PSQL_VERSION", "15")
      k3s_server_cidr_range: get_env("K3S_SERVER_CIDR_RANGE", "192.168.56.0/24")
      k3s_version: get_env("K3S_VERSION", "v1.30.2+k3s1")
      extra_server_args: ""
      extra_agent_args: ""
    }
  }

  jenkins = {
    "jenkins/creds": {
      username = "admin"
      password = "{ _RANDOM_ = 18 }"
    }
  }

  grafana = {
    "grafana/creds": {
      username = "admin"
      password = "{ _RANDOM_ = 18 }"
    }
  }

  kafka = {
    "kafka/creds": {
      clientUsername = "admin"
      clientPassword = "{ _RANDOM_ = 18 }"
    }
  }

  vault = {
    "vault/params": {
      cluster_addr: local.vault_address
    }

    "vault/creds": {
      root_token: local.vault_token
    }
  }

  database = {
    "Database/params": {
      DBClusterEndpoint: get_env("DB_CLUSTER_ENDPOINT", "192.168.56.31")
      DBClusterPort: 5432
    }
    "Database/fiesta/creds": {
      username: "fiesta"
      password: "{ _RANDOM_ = 18 }"
      database: "fiesta"
    }
  }

  global = {
    "artifactory/params" = {
      registry = get_env("ARTIFACTORY_REGISTRY", "nthedao")
    }
  }

  # psql_vms = {
  #   conn-pool: get_env("PSQL_CONN_POOL")
  #   coordinator1: get_env("PSQL_COORDINATOR_1")
  #   worker1: get_env("PSQL_WORKER_1")
  #   worker2: get_env("PSQL_WORKER_2")
  # }

}
