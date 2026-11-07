data "aws_caller_identity" "current" {}

locals {
  account      = data.aws_caller_identity.current.account_id
  envs         = ["dev", "qa", "prod", "eks"]
  boundary_arn = "arn:aws:iam::${local.account}:policy/app-boundary"
  app_roles    = "arn:aws:iam::${local.account}:role/app/*"
  app_policies = "arn:aws:iam::${local.account}:policy/app/*"
}

# Hard ceiling for every workload role created by CI.
data "aws_iam_policy_document" "boundary" {
  statement {
    sid       = "AllowWorkloads"
    actions   = ["*"]
    resources = ["*"]
  }
  statement {
    sid       = "DenyControlPlane"
    effect    = "Deny"
    actions   = ["organizations:*", "account:*", "budgets:*", "sts:AssumeRoleWithWebIdentity"]
    resources = ["*"]
  }
  # D-0114: the only IAM action a workload role may perform is passing an
  # app execution role to ECS tasks (CodePipeline ECS deploy action).
  statement {
    sid       = "DenyIamExceptPassRoleToEcsTasks"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
  statement {
    sid           = "DenyPassRoleOutsideAppExecution"
    effect        = "Deny"
    actions       = ["iam:PassRole"]
    not_resources = ["${local.app_roles}-execution"]
  }
  statement {
    sid       = "DenyStateBucket"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${local.state_bucket}", "arn:aws:s3:::${local.state_bucket}/*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "app-boundary"
  description = "Permissions boundary for CI-created workload roles"
  policy      = data.aws_iam_policy_document.boundary.json
}

data "aws_iam_policy_document" "apply_trust" {
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
      values   = [for e in local.envs : "repo:${local.repo_sub}:environment:${e}"]
    }
  }
}

resource "aws_iam_role" "gha_apply" {
  name                 = "gha-apply"
  description          = "GitHub Actions apply from protected environments"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_iam" {
  statement {
    sid       = "CreateAppRolesWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:AttachRolePolicy", "iam:PutRolePolicy", "iam:DetachRolePolicy", "iam:DeleteRolePolicy"]
    resources = [local.app_roles]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }
  statement {
    sid       = "ManageAppRoles"
    actions   = ["iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:PassRole", "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole"]
    resources = [local.app_roles]
  }
  statement {
    sid       = "ManageAppPolicies"
    actions   = ["iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:TagPolicy", "iam:UntagPolicy"]
    resources = [local.app_policies]
  }
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
  }
  statement {
    sid       = "ReadServiceLinkedRoles"
    actions   = ["iam:GetRole"]
    resources = ["arn:aws:iam::*:role/aws-service-role/*"]
  }
  statement {
    sid       = "TerraformStateWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/env/*"]
  }
  statement {
    sid       = "DenyProtectBootstrap"
    effect    = "Deny"
    actions   = ["s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration", "s3:PutEncryptionConfiguration", "s3:PutBucketPublicAccessBlock", "s3:DeleteObjectVersion"]
    resources = ["arn:aws:s3:::${local.state_bucket}", "arn:aws:s3:::${local.state_bucket}/*"]
  }
  statement {
    sid       = "DenyWriteBootstrapState"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/bootstrap/*"]
  }
  statement {
    sid     = "DenyIdentityTampering"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      aws_iam_openid_connect_provider.github.arn,
      "arn:aws:iam::${local.account}:role/gha-*",
      local.boundary_arn,
    ]
  }
  statement {
    sid       = "DenyBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary"]
    resources = ["*"]
  }
  statement {
    sid       = "DenyBudgetChanges"
    effect    = "Deny"
    actions   = ["budgets:ModifyBudget", "budgets:DeleteBudgetAction", "budgets:UpdateBudgetAction"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply_iam" {
  name   = "scoped-iam-and-guardrails"
  role   = aws_iam_role.gha_apply.id
  policy = data.aws_iam_policy_document.apply_iam.json
}

output "gha_apply_role_arn" {
  value = aws_iam_role.gha_apply.arn
}

output "app_boundary_arn" {
  value = aws_iam_policy.boundary.arn
}
