locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    public_subnets  = "value_1,value_2"
    private_subnets = "value_1,value_2"
    private_sg      = "value"
    public_sg       = "value"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

include {
  path = find_in_parent_folders()
}

terraform {
  # source = "../../../../../terraform-modules//aws/ec2"
  source = "git::git@github.com:TheDao032/devops-terraform-modules.git//aws/ec2?ref=${local.environment}"
}

inputs = {
  public_subnet_id  = split(",", dependency.vpc.outputs.public_subnets)[0]
  private_subnet_id = split(",", dependency.vpc.outputs.private_subnets)[0]

  private_sg_id = dependency.vpc.outputs.private_sg
  public_sg_id  = dependency.vpc.outputs.public_sg

  ssh_public_key = get_env("SSH_PUBLIC_KEY", "")
}
