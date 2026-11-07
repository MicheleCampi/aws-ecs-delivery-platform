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

module "security" {
  source = "../../modules/security"
  name   = var.environment
  vpc_id = module.network.vpc_id
}

output "alb_sg_id" { value = module.security.alb_sg_id }
output "task_sg_id" { value = module.security.task_sg_id }

variable "image_tag" {
  type    = string
  default = "0.1.0"
}

data "aws_ecr_repository" "app" {
  name = "delivery-app"
}

module "service" {
  source             = "../../modules/service"
  name               = "delivery-${var.environment}"
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  alb_sg_id          = module.security.alb_sg_id
  task_sg_id         = module.security.task_sg_id
  cognito = {
    user_pool_arn = module.auth.user_pool_arn
    client_id     = module.auth.client_id
    domain        = module.auth.domain
  }
  image = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"
}

output "alb_dns_name" { value = module.service.alb_dns_name }
output "cluster_name" { value = module.service.cluster_name }
output "service_name" { value = module.service.service_name }

module "auth" {
  source        = "../../modules/auth"
  name          = "delivery-${var.environment}"
  callback_urls = ["https://${module.service.alb_dns_name}/oauth2/idpresponse"]
}

output "user_pool_id" { value = module.auth.user_pool_id }
output "cognito_domain" { value = module.auth.domain }

module "pipeline" {
  source             = "../../modules/pipeline"
  name               = "delivery-${var.environment}"
  cluster_name       = module.service.cluster_name
  service_name       = module.service.service_name
  repository_url     = data.aws_ecr_repository.app.repository_url
  repository_arn     = data.aws_ecr_repository.app.arn
  execution_role_arn = module.service.execution_role_arn
}

output "pipeline_name" { value = module.pipeline.pipeline_name }
output "artifact_bucket" { value = module.pipeline.artifact_bucket }
