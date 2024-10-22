# Set common variables for the region. This is automatically pulled in in the root terragrunt.hcl configuration to
# configure the remote state bucket and pass forward to the child modules as inputs.
locals {
  environment = "dev"

  secrets = {
    jenkins = {
      jenkinsUsername      = "admin"
      jenkinsPassword      = "{ _RANDOM_ = 18 }"
    }
  }
}
