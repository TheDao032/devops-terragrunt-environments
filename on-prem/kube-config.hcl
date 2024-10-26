locals {
  host           = get_env("KUBE_HOST")
  config_path    = get_env("KUBE_CONF_PATH", "~/.kube/config")
  config_context = get_env("KUBE_CONF_CONTEXT", "k3s-local")

  client_key             = get_env("KUBE_CLIENT_KEY")
  client_certificate     = get_env("KUBE_CLIENT_CRT")
  cluster_ca_certificate = get_env("KUBE_CLIENT_CA_CRT")

  token = get_env("KUBE_TOKEN")
}
