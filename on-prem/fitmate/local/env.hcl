# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  # vault_config_vars = read_terragrunt_config(find_in_parent_folders("vault.hcl"))
  # vault_address     = local.vault_config_vars.locals.address
  # vault_token       = local.vault_config_vars.locals.token

  backend_vars            = read_terragrunt_config(find_in_parent_folders("backend.hcl"))
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

  environment  = "local"
  cluster_name = "local"

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
      url         = local.backend_gitops_url
      gitops_repo = "gitops-apps"
      insecure    = "false"
      enablelfs   = "false"
    }

    "github/creds" = {
      ssh_priv_key = local.backend_ssh_priv_key
      username     = local.backend_github_username
      token        = local.backend_github_token
    }

    "argocd/params" = {
    }

    "argocd/creds" = {
      username = "admin"
      password = "{ _RANDOM_ = 18 }"
    }

    # PostgreSQL/Citus (on-prem, NOT k8s) — consumed by the `database` unit.
    # superuser (tf_admin) is the role the cyrilgdn provider LOGS IN as, so its password must
    # be a STABLE, pre-provisioned value (NOT _RANDOM_): the same PG_ADMIN_PASSWORD is used to
    # create the role in the citus-docker entrypoint AND stored here for the module to read.
    "database/superuser/creds" = {
      username = "tf_admin"
      password = get_env("PG_ADMIN_PASSWORD", "change-me-tf-admin")
    }
    # Per-application-service DB roles. app (read-write, owns the db) / ro (read-only). app/ro are
    # CREATED by the database module, so _RANDOM_ is fine — Vault is the source of truth and the
    # module sets each role's password to what lands here. Keys grouped per service:
    # database/<service>/<role>/creds. Real FITMate services with Postgres (6 Go services):
    #   trainee
    "database/trainee/app/creds" = { username = "trainee_app", password = "{ _RANDOM_ = 18 }" }
    "database/trainee/ro/creds"  = { username = "trainee_ro", password = "{ _RANDOM_ = 18 }" }
    #   trainer
    "database/trainer/app/creds" = { username = "trainer_app", password = "{ _RANDOM_ = 18 }" }
    "database/trainer/ro/creds"  = { username = "trainer_ro", password = "{ _RANDOM_ = 18 }" }
    #   booking
    "database/booking/app/creds" = { username = "booking_app", password = "{ _RANDOM_ = 18 }" }
    "database/booking/ro/creds"  = { username = "booking_ro", password = "{ _RANDOM_ = 18 }" }
    #   inquiry
    "database/inquiry/app/creds" = { username = "inquiry_app", password = "{ _RANDOM_ = 18 }" }
    "database/inquiry/ro/creds"  = { username = "inquiry_ro", password = "{ _RANDOM_ = 18 }" }
    #   admin
    "database/admin/app/creds" = { username = "admin_app", password = "{ _RANDOM_ = 18 }" }
    "database/admin/ro/creds"  = { username = "admin_ro", password = "{ _RANDOM_ = 18 }" }
    #   payment — WRITE-ONLY today (config/prod minimal, gateway unbuilt) → app role only, no ro
    "database/payment/app/creds" = { username = "payment_app", password = "{ _RANDOM_ = 18 }" }
    #   keycloak — its own db + owner role (runs its OWN schema migrations → full DDL, no ro).
    #   Connects DIRECT to :5432 (NOT pgbouncer transaction pooling — breaks its advisory locks).
    "database/keycloak/app/creds" = { username = "keycloak_app", password = "{ _RANDOM_ = 18 }" }

    # "jenkins/creds" = {
    #   username = "admin"
    #   password = "{ _RANDOM_ = 18 }"
    # }
    #
    # "grafana/creds" = {
    #   username = "admin"
    #   password = "{ _RANDOM_ = 18 }"
    # }
    #
    # "loki/creds" = {
    #   username = "admin"
    #   password = "{ _RANDOM_ = 18 }"
    # }
    #
    # "kafka/creds" = {
    #   clientUsername = "admin"
    #   clientPassword = "{ _RANDOM_ = 18 }"
    # }

    # Commented until Vault is deployed + initialized — vault_address / vault_token
    # come from vault.hcl (uncommented above at that stage).
    # "vault/params" = {
    #   clusterAddr = local.vault_address
    # }
    #
    # "vault/creds" = {
    #   rootToken = local.vault_token
    # }

    # "database/params" = {
    #   DBClusterEndpoint = get_env("DB_CLUSTER_ENDPOINT", "192.168.56.31")
    #   DBClusterPort     = 5432
    # }
    #
    # "database/admin-service/creds" = {
    #   username = "fiesta"
    #   password = "{ _RANDOM_ = 18 }"
    #   database = "fiesta"
    # }

    # "podRestartCollector/creds" = {
    #   slackWebhookUrl = get_env("SLACK_WEBHOOK_URL", "")
    # }
  }

  # cloudflare_api_token = get_env("CLOUDFLARE_API_TOKEN", "")

  tags = {
    created_by    = "terraform"
    environment   = local.environment
    organiazation = local.org_infras_org
  }


}
