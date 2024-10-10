# Terragrunt environments configuration
## Introduction
This repository is used to setup infrastructure using Terragrunt and Terraform. Infrastructure as code configurations are written in HCL.
## Locations and environments:
- [on-prem/dev](on-prem/dev): DEV environment in on premise location (on-prem).
## Environment structure:
- Each environment is placed in the following directory structure: `<LOCATION>/<ENVIRONMENT>`. Here's the detailed structure (this can be subjected to changes in the future):

+ `<LOCATION>/location.hcl`: Azure subscription configuration.
+ `<LOCATION>/backend.hcl`: Environment region configuration.
+ `<LOCATION>/kube-config.hcl`: Environment region configuration.
+ `<LOCATION>/<ENVIRONMENT>/env.hcl`: Environment configuration (env name, etc).
+ `<LOCATION>/<ENVIRONMENT>/<RESOURCE>/terragrunt.hcl`: Resource configuration using Terragrunt.

- In each environment, sets of materials maybe categorized in some ways. For example: infra, network, etc. Refer to each environment for more details.
## Apply
### Authentication
#### Azure resources
- Refer to [Terraform AzureRM Authentication](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure) for how to authenticate to Azure for terraform operations.
- For local execution, it is recommended to use `Azure CLI` or `Managed Service Identity` for authentication.
- For execution in CIs or automated environments, it is recommended to use `Managed Service Identity` or `OpenID Connect` for authentication.
### Execution
- `cd` to each environment region (e.g: `on-prem/dev`).
- Run `rm -rf **/.terragrunt-cache* && rm -rf **/.terraform.lock.hcl` to remove existing caches.
- Run `terragrunt run-all init` to initialize all environment modules.
- Run `terragrunt run-all apply` to apply changes to infrastructure.
