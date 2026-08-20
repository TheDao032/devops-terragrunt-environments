# SHARED (cluster-wide) tier — applied ONCE for the whole fitmate k3s cluster.
#
# One k3s cluster hosts every environment (dev/stg/prod). This tier owns the resources that are
# NOT split by env: the platform (init-resources: Vault, External-Secrets, Traefik, cert-manager,
# Gateway CRDs), cluster RBAC (service-accounts), and the shared operators/tooling (ops-tools:
# Keycloak operator+instance, ArgoCD, Kafka, Redis). Per-env resources (vault-auths roles,
# vault-secrets app creds, database, keycloak realms) live under dev/ stg/ prod/.
#
# `secrets` here = PLATFORM secrets only, seeded into the Vault KV at fitmate/data/platform/*
# (path_prefix "platform/"). Per-env APP secrets live in each env's env.hcl → fitmate/data/<env>/*.
#
# Platform hostnames are cluster-wide (one Vault, one ArgoCD, one Keycloak) → they use the fixed
# cluster suffix `k3s.fitmate` (NOT k3s.<env>). Per-env app hostnames are <app>.<env>.k3s.fitmate.
locals {
  backend_vars            = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  backend_docker_registry = local.backend_vars.locals.docker_registry
  backend_docker_username = local.backend_vars.locals.docker_username
  backend_docker_token    = local.backend_vars.locals.docker_token
  backend_docker_email    = local.backend_vars.locals.docker_email

  backend_gitops_url   = local.backend_vars.locals.gitops_url
  backend_ssh_priv_key = local.backend_vars.locals.ssh_private_key

  backend_github_token    = local.backend_vars.locals.github_token
  backend_github_username = local.backend_vars.locals.github_username

  backend_artifactory_registry = local.backend_vars.locals.artifactory_registry

  org_vars       = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  org_infras_org = local.org_vars.locals.infras_organization

  # tier marker (used for path/tag scoping) + the cluster-wide hostname suffix.
  environment    = "shared"
  cluster_name   = "fitmate"
  cluster_suffix = "fitmate" # platform hosts render as <svc>.k3s.fitmate

  # ── PLATFORM secrets (fitmate/data/platform/*) — consumed by shared ops-tools + init-resources.
  #    App-level, per-env secrets (database/<svc>, <svc>/params, realm seed users, ghcr-pull) are
  #    NOT here — they live in dev/ stg/ prod/ env.hcl.
  secrets = {
    "artifactory/params" = {
      registry = local.backend_artifactory_registry
    }

    "docker/creds" = {
      username = local.backend_docker_username
      password = local.backend_docker_token
      email    = local.backend_docker_email
    }

    "docker/params" = {
      registry = local.backend_docker_registry
    }

    "github/params" = {
      # fitmate-gitops (private, HTTPS) under FITMate-Platform — the canonical GitOps repo (ADR-032).
      url         = "https://github.com/FITMate-Platform"
      gitops_repo = "fitmate-gitops"
      insecure    = "false"
      enablelfs   = "false"
    }

    "github/creds" = {
      ssh_priv_key = local.backend_ssh_priv_key
      username     = local.backend_github_username
      token        = local.backend_github_token
    }

    "argocd/params" = {}

    "argocd/creds" = {
      username = "admin"
      password = "{ _RANDOM_ = 18 }"
    }

    # PostgreSQL/Citus superuser — ONE PG server backs all envs, so the tf_admin login is shared.
    # STABLE value (NOT _RANDOM_): the same PG_ADMIN_PASSWORD creates the role in the citus
    # entrypoint AND is stored here for the cyrilgdn provider to log in as. Each env's `database`
    # unit reads this shared platform cred to provision its own env-scoped DBs/roles.
    "database/superuser/creds" = {
      username = "tf_admin"
      password = get_env("PG_ADMIN_PASSWORD", "change-me-tf-admin")
    }

    # Keycloak master-realm BOOTSTRAP ADMIN (CR spec.bootstrapAdmin) — the SHARED Keycloak instance's
    # admin. Per-env REALMS (fitmate-dev/stg + fitmate) are configured by each env's keycloak unit
    # using THIS admin. Separate from the keycloak_app DB role (that's created per env's database).
    "keycloak/admin/creds" = { username = "admin", password = "{ _RANDOM_ = 20 }" }

    # Keycloak server's STORAGE DB owner role (db `keycloak`, created by shared/database/keycloak).
    # Platform-level: one shared Keycloak instance → one keycloak DB. Consumed by shared/ops-tools
    # (Keycloak CR db config) + shared/database/keycloak (role creation).
    "database/keycloak/app/creds" = { username = "keycloak_app", password = "{ _RANDOM_ = 18 }" }

    # Kafka + Redis are SHARED single instances (one each). Envs are isolated logically (topic/key
    # prefixes / per-env namespaces), so the SASL/auth creds are platform-level. Per-env app ESO
    # roles are granted read on platform/kafka + platform/redis to consume them.
    "kafka/creds" = { clientUsername = "admin", clientPassword = "{ _RANDOM_ = 18 }" }
    "redis/creds" = { password = "{ _RANDOM_ = 18 }" }

    # Grafana admin (IN-13). Platform-level: ONE monitoring stack watches every env, so this is not
    # env-foldered. Consumed by shared/ops-tools → kube-prometheus-stack `grafana.adminPassword`.
    #
    # ⚠️ This MUST be set. The chart's default admin password is the well-known literal
    # `prom-operator`, and Grafana is exposed on a routable hostname (grafana.k3s.fitmate), so
    # leaving the default is a cluster-wide credential published on the network.
    #
    # ⚠️ ROTATION HAZARD: this is a `_RANDOM_`, so re-applying shared/vault-secrets re-rolls it —
    # the same cascade that has previously broken DB roles and locked out the Keycloak admin.
    # Grafana stores the admin password in its own DB on first boot and does NOT re-read this on
    # later syncs, so a re-roll silently desynchronises Vault from the live Grafana. If it is ever
    # re-rolled, reset in-place via `grafana-cli admin reset-admin-password` rather than assuming
    # the new Vault value took effect.
    "grafana/creds" = { username = "admin", password = "{ _RANDOM_ = 20 }" }
  }

  tags = {
    created_by   = "terraform"
    environment  = local.environment
    organization = local.org_infras_org
  }
}
