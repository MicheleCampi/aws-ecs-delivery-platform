terraform {
  required_version = ">= 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    bucket       = "michele-tfstate-aws-ecs-delivery"
    key          = "env/shared/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-west-1"
  default_tags {
    tags = {
      project     = "aws-ecs-delivery-platform"
      managed_by  = "terraform"
      environment = "shared"
    }
  }
}

module "ecr" {
  source = "../../modules/ecr"
  name   = "delivery-app"
}

output "ecr_repository_url" { value = module.ecr.repository_url }
