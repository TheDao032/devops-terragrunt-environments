locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  org_config_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org_name        = local.org_config_vars.locals.infras_organization

  vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault.hcl"))
  vault_address     = local.vault_config_vars.locals.vault_address # host-side (vault.k3s.local) — NOT resolvable from inside the cluster

  # In-cluster Vault address for the ESO SecretStore. External Secrets runs as a POD, so it must use
  # cluster DNS (CoreDNS), NOT the host-only `vault.k3s.local` ingress hostname (pods can't resolve
  # it → "no such host" → InvalidProviderConfig). vault-active = the unsealed active node; HTTPS on
  # 8200. The ESO controller runs with VAULT_SKIP_VERIFY=true, so the cert-manager private CA needs
  # no caBundle here (lab); for prod, add caProvider → the vault-tls-ca secret instead.
  vault_incluster_address = "https://vault-active.vault.svc.cluster.local:8200"

  # secret_store_name = "vault-backend"
  # secrets          = local.environment_vars.locals.secrets
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/${local.org_name}/ops-tools"
  # source = "git::git@github.com:TheDao032/devops-terraform-modules.git//on-prem/${local.org_name}/k3s-resources?ref=${local.environment}"
}

# ── Bootstrap gate ────────────────────────────────────────────────────────────
# Skip until Vault is genuinely up+unsealed (this unit reads vault-auths/vault-secrets
# outputs + the vault provider). Gate on ACTUAL reachability via the health endpoint (a
# stale VAULT_TOKEN hardcoded in .envrc.local makes a token-presence gate useless):
# `curl -f` fails while Vault is down/sealed → exclude; 200 → include. See on-prem/vault.hcl.
exclude {
  if = run_cmd("--terragrunt-quiet", "bash", "-c",
    "curl -fs -o /dev/null --max-time 3 $${VAULT_ADDR:-http://vault.k3s.local}/v1/sys/health && echo false || echo true"
  ) == "true"
  actions = ["all"]
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "vault" {
  path = find_in_parent_folders("vault.hcl")
}


dependency "vault-auths" {
  config_path = "../vault-auths"
  mock_outputs = {
    roles = {
      external-secrets = {
        role_id      = "mock",
        secret_id    = "mock",
        client_token = "mock"
      }
    }
  }

  # mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_strategy_with_state = "shallow"
}

# ArgoCD reads GitHub/ArgoCD creds from vault-secrets and the ESO SecretStore name from
# external-secrets. mock_outputs let the FIRST bring-up pass plan (ArgoCD off) before those
# stacks exist; the SECOND pass (ArgoCD on) uses their real, applied outputs. Apply order:
#   k3s-resources (argocd_conf absent) → vault-secrets → external-secrets → k3s-resources (this).
dependency "vault-secrets" {
  config_path = "../vault-secrets"
  mock_outputs = {
    secrets = {
      "github/params" = { url = "https://github.com/MOCK", gitops_repo = "gitops-apps" }
      "github/creds"  = { ssh_priv_key = "MOCK" }
      "argocd/creds"  = { password = "MOCK" }
    }
  }

  # mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_strategy_with_state = "shallow"
}

# dependency "external-secrets" {
#   config_path = "../external-secrets"
#   mock_outputs = {
#     gitops_backend_name = "gitops-backend"
#   }
#   mock_outputs_merge_strategy_with_state = "shallow"
# }

inputs = {
  # ArgoCD (core). Present ⇒ addons.tf enables the argocd + argocd-routing modules (see the
  # two-pass note there). Reads live creds/store name from the vault-secrets + external-secrets
  # dependency blocks below (mocked so the first bring-up pass still plans while ArgoCD is off).
  argocd_conf = {
    helm = {
      # Latest argo-helm chart (2026-07-09). NOTE: 3-major jump from the old 7.8.10 scaffold —
      # our values only touch stable keys (server.insecure, credentialTemplates, repositories),
      # but skim the 8.0.0 / 9.0.0 / 10.0.0 breaking-change notes before the prod tenants adopt it.
      chart_version = "10.1.3"
      namespace     = "argocd"
      repository    = "https://argoproj.github.io/argo-helm"
      release_name  = "argo-cd"
    }

    # Only `domain` is consumed (values.yml.tftpl global.domain). Routing is Gateway API below.
    ingress = {
      domain = "argocd.k3s.${local.environment}"
    }

    # Names for the chart's ExternalSecrets (applied after the release; reconcile once the gitops
    # SecretStore exists). store_name = the ESO SecretStore in the gitops ns (external-secrets stack).
    secret = {
      vault_address       = local.vault_incluster_address                                      # in-cluster (ESO pod) — NOT vault.k3s.local
      approle_path        = "approle"                                                          # auth mount (vault_auth_backend.main default path)
      role_id             = dependency.vault-auths.outputs.roles["external-secrets"].role_id   # public
      secret_id           = dependency.vault-auths.outputs.roles["external-secrets"].secret_id # credential
      approle_secret_name = "argocd-approle"
      argocd_secret_name  = "argocd-ex-secret"

      store_name                = "argocd-store-backend"
      docker_config_secret_name = "docker-ex-configjson"
      docker_token_secret_name  = "docker-ex-token"
      github_secret_name        = "github-ex-ssh-priv-key"
    }

    github = {
      url          = dependency.vault-secrets.outputs.secrets["github/params"]["url"]
      gitops_repo  = dependency.vault-secrets.outputs.secrets["github/params"]["gitops_repo"]
      ssh_priv_key = dependency.vault-secrets.outputs.secrets["github/creds"]["ssh_priv_key"]
    }

    common = {
      admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password"]
    }

    # UI/API via Gateway API HTTPRoute on the shared traefik-gateway `web` listener. HTTPRoute
    # lives in `argocd` (same ns as the backend Service → no ReferenceGrant); parentRef crosses
    # into `traefik` (allowed, listener is from:All). backend_name = the argocd-server Service.
    # CONFIRMED via `kubectl get svc -n argocd`: chart names it `<release>-argocd-server` →
    # release `argo-cd` yields `argo-cd-argocd-server` (Service port http:80).
    routing = {
      httproutes = [
        {
          name              = "argocd"
          namespace         = "argocd"
          gateway_name      = "traefik-gateway"
          gateway_namespace = "traefik"
          section_name      = "web"
          hostnames         = ["argocd.k3s.${local.environment}"]
          path_prefix       = "/"
          backend_name      = "argo-cd-argocd-server"
          backend_port      = 80
        }
      ]
    }
  }

  # argocd_img_upd_conf = {
  #   helm = {
  #     chart_version = "1.2.4"
  #     namespace     = "argocd"
  #     repository    = "https://argoproj.github.io/argo-helm"
  #     release_name  = "argocd-image-updater"
  #   }
  #
  #   docker = {
  #     secret_name  = "docker-ex-token"
  #     organization = dependency.vault-secrets.outputs.secrets["docker/creds"]["username"]
  #   }
  #
  #   common = {
  #     admin_password = dependency.vault-secrets.outputs.secrets["argocd/creds"]["password"]
  #   }
  # }
  #
  # kafka_conf = {
  #   helm = {
  #     chart_version = "31.0.0"
  #     image_tag     = "3.9.0-debian-12-r1"
  #     namespace     = "tools"
  #     repository    = "https://charts.bitnami.com/bitnami"
  #     release_name  = "kafka"
  #   }
  #
  #   controller = {
  #     replica_count = 1
  #     hpa_active    = true
  #     mount_path    = "/bitnami/kafka/controller"
  #     size          = "8Gi"
  #     min_replicas  = 1
  #     max_replicas  = 5
  #   }
  #
  #   broker = {
  #     replica_count = 1
  #     hpa_active    = true
  #     mount_path    = "/bitnami/kafka/broker"
  #     size          = "8Gi"
  #     min_replicas  = 1
  #     max_replicas  = 5
  #   }
  #
  #   sasl = {
  #     client_username : dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientUsername"]
  #     client_password : dependency.vault-secrets.outputs.secrets["kafka/creds"]["clientPassword"]
  #   }
  #
  #   common = {
  #   }
  # }
  #
}
