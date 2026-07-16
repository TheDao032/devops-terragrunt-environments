# NOTE: these read TG_KUBE_* (set in the repo .envrc), NOT the bare KUBE_* names. The
# hashicorp/kubernetes provider natively consumes KUBE_HOST/KUBE_CLIENT_CERT_DATA/etc. as its
# own config env vars and would override the inline base64decode(...) certs in provider-kube.tf
# with our base64 (non-PEM) values → "not a valid PEM encoded certificate" on any kubernetes_*
# stack. The TG_ prefix keeps these visible to terragrunt get_env() but hidden from the provider.
locals {
  host           = get_env("TG_KUBE_HOST")
  config_path    = get_env("TG_KUBE_CONFIG_PATH", "~/.kube/config")
  config_context = get_env("TG_KUBE_CTX", "k3s-local")

  client_key             = get_env("TG_KUBE_CLIENT_KEY_DATA")
  client_certificate     = get_env("TG_KUBE_CLIENT_CERT_DATA")
  cluster_ca_certificate = get_env("TG_KUBE_CLUSTER_CA_CERT_DATA")

  token = get_env("TG_KUBE_TOKEN", "")
}
