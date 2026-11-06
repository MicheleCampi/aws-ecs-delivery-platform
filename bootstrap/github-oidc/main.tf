terraform {
  required_version = "~> 1.15"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
  default_tags {
    tags = {
      project    = "aws-ecs-delivery-platform"
      managed_by = "terraform"
      root       = "bootstrap/github-oidc"
    }
  }
}

locals {
  repo         = "MicheleCampi/aws-ecs-delivery-platform"
  state_bucket = "michele-tfstate-aws-ecs-delivery"
}

# Thumbprint omitted: AWS validates GitHub's OIDC TLS chain via its trusted CA library.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.repo}:pull_request"]
    }
  }
}

resource "aws_iam_role" "gha_plan" {
  name                 = "gha-plan"
  description          = "GitHub Actions PR plan: read-only plus Terraform lockfile writes"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.state_bucket}"]
  }
  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/*"]
  }
  statement {
    sid       = "WriteLockfileOnly"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state-plan"
  role   = aws_iam_role.gha_plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "gha_plan_role_arn" {
  value = aws_iam_role.gha_plan.arn
}
