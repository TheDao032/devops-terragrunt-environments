locals {
  host           = get_env("KUBE_HOST")
  config_path    = get_env("KUBE_CONFIG_PATH", "~/.kube/config")
  config_context = get_env("KUBE_CTX", "k3s-local")

  client_key             = get_env("KUBE_CLIENT_KEY_DATA")
  client_certificate     = get_env("KUBE_CLIENT_CERT_DATA")
  cluster_ca_certificate = get_env("KUBE_CLUSTER_CA_CERT_DATA")

  token = get_env("KUBE_TOKEN")
}
