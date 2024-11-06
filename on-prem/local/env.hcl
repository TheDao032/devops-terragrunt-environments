# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  environment = "local"

  k3s = {
    "k3s/params": {
      server-1: get_env("K3S_SERVER_1")
      server-2: get_env("K3S_SERVER_2")
      agent-1: get_env("K3S_AGENT_1")
      agent-2: get_env("K3S_AGENT_2")
      api_endpoint: get_env("K3S_SERVER_1")
      keepalived_virtual_ip: get_env("KEEPALIVED_VIRTUAL_IP")
      keepalived_nw_interface: get_env("KEEPALIVED_NW_INTERFACE")
      load_balancer_port: get_env("LOAD_BALANCER_PORT")
      psql_version: get_env("PSQL_VERSION")
      k3s_server_cidr_range: get_env("K3S_SERVER_CIDR_RANGE")
      k3s_version: get_env("K3S_VERSION")
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
      cluster_addr: get_env("VAULT_ADDR")
    }

    "vault/creds": {
      root_token: get_env("VAULT_TOKEN")
    }
  }

  database = {
    "Database/params": {
      DBClusterEndpoint: get_env("DB_CLUSTER_ENDPOINT")
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
      registry = get_env("ARTIFACTORY_REGISTRY")
    }
  }

  # psql_vms = {
  #   conn-pool: get_env("PSQL_CONN_POOL")
  #   coordinator1: get_env("PSQL_COORDINATOR_1")
  #   worker1: get_env("PSQL_WORKER_1")
  #   worker2: get_env("PSQL_WORKER_2")
  # }

}
