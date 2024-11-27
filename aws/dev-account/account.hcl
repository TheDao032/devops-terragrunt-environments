# Set account-wide variables. These are automatically pulled in to configure the remote state bucket in the root
# terragrunt.hcl configuration.
locals {
  account_name = get_env("ACCOUNT_NAME")
  account_id   = get_env("ACCOUNT_ID")

  tags = {
    CreatedBy = "Terraform"
  }
}
