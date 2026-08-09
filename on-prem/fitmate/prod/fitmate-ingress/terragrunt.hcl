locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

terraform {
  source = "../../../../../devops-terraform-modules//on-prem/shared/traefik-ingress"
}

# Deploys INTO the cluster (kubernetes + kubectl providers from root.hcl) → cluster must be up. Adds
# the *.fitmate.me Traefik Ingresses that the cloudflare-tunnel routes hand off to. Apply AFTER the
# backing platform services exist (uncomment a route once its Service is (re)deployed).
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "kube" {
  path = find_in_parent_folders("kube.hcl")
}

inputs = {
  # host -> backend Service. Confirmed live on the cluster (2026-08-03): only vault + traefik so far.
  routes = {
    # Vault UI — HTTPS backend on :8200 via the vault-active svc; reuse the Helm chart's ServersTransport.
    "vault.fitmate.me" = {
      namespace         = "vault"
      service           = "vault-active"
      port              = 8200
      https             = true
      servers_transport = "vault-backend@kubernetescrd"
    }

    # ── Uncomment each as its Service is (re)deployed on the cluster (verify name/port/ns first) ──
    "auth.fitmate.me" = { # Keycloak (public auth)
      namespace = "keycloak"
      service   = "keycloak-service"
      port      = 8080
    }

    "argocd.fitmate.me" = { # ArgoCD UI (Access-gated)
      namespace = "argocd"
      service   = "argo-cd-argocd-server" # chart release is `argo-cd` → svc `argo-cd-argocd-server` (NOT `argocd-server`)
      port      = 80                      # server.insecure=true → HTTP on :80; edge terminates TLS
    }

    # "kafka-ui.fitmate.me" = {                    # kafka-ui (Access-gated) — confirm ns/svc/port
    #   namespace = "platform"
    #   service   = "kafka-ui"
    #   port      = 8080
    # }
  }

  # Traefik dashboard (api@internal) — Access-gated in Phase 6.
  traefik_dashboard = {
    host      = "traefik.fitmate.me"
    namespace = "traefik"
  }
}
