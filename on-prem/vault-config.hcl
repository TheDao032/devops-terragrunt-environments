locals {
  address = get_env("VAULT_ADDR", "https://192.168.56.11:8200")
  token   = get_env("VAULT_TOKEN", "hvs.6BcpGlzgfBseOdTavyAPWAxc")
}
