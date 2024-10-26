# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  environment = "local"

  secrets = {
    jenkinsUsername = "admin"
    jenkinsPassword = "{ _RANDOM_ = 18 }"
    grafanaUsername = "admin"
    grafanaPassword = "{ _RANDOM_ = 18 }"
    kafkaClientPassword = "{ _RANDOM_ = 18 }"
  }

  k3s_vms = {
    server_1: get_env("K3S_SERVER_1")
    server_2: get_env("K3S_SERVER_2")
    agent_1: get_env("K3S_AGENT_1")
    agent_2: get_env("K3S_AGENT_2")
  }

  k3s_envs = {
    api_endpoint: get_env("K3S_SERVER_1")

    keepalived_virtual_ip: get_env("KEEPALIVED_VIRTUAL_IP")
    load_balancer_port: get_env("LOAD_BALANCER_PORT")
    psql_version: get_env("PSQL_VERSION")
    k3s_server_cidr_range: get_env("K3S_SERVER_CIDR_RANGE")
    k3s_version: get_env("K3S_VERSION")
    extra_server_args: "",
    extra_agent_args: "",
  }

  # psql_vms = {
  #   conn-pool: get_env("PSQL_CONN_POOL")
  #   coordinator1: get_env("PSQL_COORDINATOR_1")
  #   worker1: get_env("PSQL_WORKER_1")
  #   worker2: get_env("PSQL_WORKER_2")
  # }
  #
  # vault_vms = {
  #   server: get_env("VAULT_SERVER")
  # }
}
