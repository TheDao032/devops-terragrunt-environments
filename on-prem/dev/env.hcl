# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  environment = "dev"

  secrets = {
    jenkinsUsername = "admin"
    jenkinsPassword = "{ _RANDOM_ = 18 }"
    grafanaUsername = "admin"
    grafanaPassword = "{ _RANDOM_ = 18 }"
    kafkaClientUsername = "admin"
    kafkaClientPassword = "{ _RANDOM_ = 18 }"
  }

  k3s_params = {
    server-1: get_env("K3S_SERVER_1")
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

  vault_params = {
    cluster_addr: get_env("VAULT_ADDR")
  }

  vault_secrets = {
    root_token: get_env("VAULT_TOKEN")
  }

}
