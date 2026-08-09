# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  hostname           = "app.terraform.io"
  tf_organization    = "nthedao_org"
  tf_workspaces_name = "nthedao_ws"

  docker_registry = get_env("DOCKER_REGISTRY", "https://index.docker.io/v1/")
  docker_token    = get_env("DOCKER_TOKEN", "")
  docker_username = get_env("DOCKER_USERNAME", "nthedao")
  docker_email    = get_env("DOCKER_EMAIL", "nthedao2705@gmail.com")

  github_token    = get_env("GITHUB_TOKEN", "")
  github_username = get_env("GITHUB_USERNAME", "TheDao032")

  gitops_url      = "git@github.com:${local.github_username}"
  ssh_private_key = get_env("SSH_PRIVATE_KEY", "")

  artifactory_registry = get_env("ARTIFACTORY_REGISTRY", "nthedao")

  # ── Kubernetes provider config (consolidated from the per-tenant kube-config.hcl) ───────────
  # Fallback get_env: TG_KUBE_* first (local dev — hidden from the kubernetes provider's native
  # env reading; see the vault note terraform-kube-provider-env-collision), then bare KUBE_*
  # (CI/Jenkins raw-PEM path). Empty defaults so `terragrunt` parsing never fails before the env
  # is exported. root.hcl / terragrunt.onprems.hcl read these into the kube/helm/kubectl providers.
  host           = get_env("TG_KUBE_HOST", get_env("KUBE_HOST", ""))
  config_path    = get_env("TG_KUBE_CONFIG_PATH", get_env("KUBE_CONFIG_PATH", "~/.kube/config"))
  config_context = get_env("TG_KUBE_CTX", get_env("KUBE_CTX", "k3s-local"))

  client_key             = get_env("TG_KUBE_CLIENT_KEY_DATA", get_env("KUBE_CLIENT_KEY_DATA", ""))
  client_certificate     = get_env("TG_KUBE_CLIENT_CERT_DATA", get_env("KUBE_CLIENT_CERT_DATA", ""))
  cluster_ca_certificate = get_env("TG_KUBE_CLUSTER_CA_CERT_DATA", get_env("KUBE_CLUSTER_CA_CERT_DATA", ""))

  token = get_env("TG_KUBE_TOKEN", get_env("KUBE_TOKEN", ""))
}
