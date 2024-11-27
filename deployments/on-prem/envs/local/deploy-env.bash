#!/bin/bash

set -euo pipefail

ENVIRONMENT=${1}
LOCATION=${LOCATION:-"on-prem"}

SECRETS_TYPE=${SECRETS_TYPE:-"env"}
K3S_SECRETS_PATH=${K3S_SECRETS_PATH:-"${ENVIRONMENT}/k3s/creds"}
# VAULT_SECRETS_PATH=${VAULT_SECRETS_PATH:-"${ENVIRONMENT}/vault/creds"}

export VAULT_ADDR=${VAULT_ADDR:-""}
export VAULT_TOKEN=${VAULT_TOKEN:-""}
export VAULT_SKIP_VERIFY=true
vault login -address=${VAULT_ADDR} -method=token $(echo ${VAULT_TOKEN})

export KUBE_CLIENT_KEY_DATA=$(vault kv get -field=client_key ${K3S_SECRETS_PATH})
export KUBE_CLIENT_CERT_DATA=$(vault kv get -field=client_crt ${K3S_SECRETS_PATH})
export KUBE_CLUSTER_CA_CERT_DATA=$(vault kv get -field=client_ca_crt ${K3S_SECRETS_PATH})
export KUBE_TOKEN=$(vault kv get -field=token ${K3S_SECRETS_PATH})
export KUBE_HOST=$(vault kv get -field=host ${K3S_SECRETS_PATH})
export CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN:-""}


if [[ "${SECRETS_TYPE}" == "env" ]]; then
  export K3S_SERVER_1=${K3S_SERVER_1:-"192.168.56.11"}
  export K3S_SERVER_2=${K3S_SERVER_2:-"192.168.56.12"}
  export K3S_AGENT_1=${K3S_AGENT_1:-"192.168.56.21"}
  export K3S_AGENT_2=${K3S_AGENT_2:-"192.168.56.22"}

  export KEEPALIVED_VIRTUAL_IP=${KEEPALIVED_VIRTUAL_IP:-"192.168.56.100"}
  export KEEPALIVED_NW_INTERFACE=${KEEPALIVED_NW_INTERFACE:-"eth1"}
  export LOAD_BALANCER_PORT=${LOAD_BALANCER_PORT:-6445}
  export PSQL_VERSION=${PSQL_VERSION:-15}
  export K3S_SERVER_CIDR_RANGE=${K3S_SERVER_CIDR_RANGE:-"192.168.56.0/24"}
  export K3S_VERSION=${K3S_VERSION:-"v1.30.2+k3s1"}

  export DB_CLUSTER_ENDPOINT=${DB_CLUSTER_ENDPOINT:-"192.168.56.31"}
  export ARTIFACTORY_REGISTRY=${ARTIFACTORY_REGISTRY:-"nthedao"}
fi
