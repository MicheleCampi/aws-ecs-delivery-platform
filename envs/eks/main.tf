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
    key          = "env/eks/terraform.tfstate"
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

variable "environment" { type = string }
variable "vpc_cidr" { type = string }
variable "nat_mode" { type = string }
variable "image_tag" { type = string }
variable "node_instance_type" {
  type    = string
  default = "t3.small"
}
variable "admin_principal_arns" {
  description = "Extra IAM principals with cluster admin (e.g. the local identity used for kubectl in K2)"
  type        = list(string)
  default     = []
}

locals {
  name     = "delivery-${var.environment}"
  boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/app-boundary"
}

data "aws_caller_identity" "current" {}

data "aws_ecr_repository" "app" {
  name = "delivery-app"
}

module "network" {
  source              = "../../modules/network"
  name                = var.environment
  cidr                = var.vpc_cidr
  nat_mode            = var.nat_mode
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

data "aws_iam_policy_document" "cluster_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name                 = "eks-cluster"
  path                 = "/app/"
  assume_role_policy   = data.aws_iam_policy_document.cluster_trust.json
  permissions_boundary = local.boundary
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "node_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name                 = "eks-node"
  path                 = "/app/"
  assume_role_policy   = data.aws_iam_policy_document.node_trust.json
  permissions_boundary = local.boundary
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_cluster" "this" {
  name     = local.name
  role_arn = aws_iam_role.cluster.arn

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = module.network.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"] # declared limit: IAM-authenticated, cluster lives < 1 h
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_access_entry" "admin" {
  for_each      = toset(var.admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "admin" {
  for_each      = toset(var.admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.admin]
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = module.network.private_subnet_ids
  instance_types  = [var.node_instance_type]
  ami_type        = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

output "cluster_name" { value = aws_eks_cluster.this.name }
output "cluster_version" { value = aws_eks_cluster.this.version }
output "image" { value = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}" }
output "nat_gateway_count" { value = module.network.nat_gateway_count }
