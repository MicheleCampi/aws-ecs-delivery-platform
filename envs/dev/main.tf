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
    key          = "env/dev/terraform.tfstate"
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
      environment = var.environment
    }
  }
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "nat_mode" {
  type = string
}

module "network" {
  source   = "../../modules/network"
  name     = var.environment
  cidr     = var.vpc_cidr
  nat_mode = var.nat_mode
}

output "vpc_id" { value = module.network.vpc_id }
output "private_subnet_ids" { value = module.network.private_subnet_ids }
output "nat_gateway_count" { value = module.network.nat_gateway_count }
