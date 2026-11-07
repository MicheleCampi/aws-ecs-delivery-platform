data "aws_caller_identity" "this" {}
data "aws_region" "this" {}
locals {
  account    = data.aws_caller_identity.this.account_id
  boundary   = "arn:aws:iam::${local.account}:policy/${var.permissions_boundary_name}"
  source_key = "source/app.zip"
  registry   = split("/", var.repository_url)[0]
}
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.name}-pipeline-${local.account}"
  force_destroy = true
}
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${var.name}"
  retention_in_days = 7
}
data "aws_iam_policy_document" "build_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "build" {
  name                 = "${var.name}-build"
  path                 = "/app/"
  permissions_boundary = local.boundary
  assume_role_policy   = data.aws_iam_policy_document.build_assume.json
}
data "aws_iam_policy_document" "build" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.build.arn}:*"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
    "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"]
    resources = [var.repository_arn]
  }
}
resource "aws_iam_role_policy" "build" {
  role   = aws_iam_role.build.id
  policy = data.aws_iam_policy_document.build.json
}
resource "aws_codebuild_project" "this" {
  name          = var.name
  service_role  = aws_iam_role.build.arn
  build_timeout = 20
  artifacts { type = "CODEPIPELINE" }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "REPO_URL"
      value = var.repository_url
    }
    environment_variable {
      name  = "REGISTRY"
      value = local.registry
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.container_name
    }
  }
  logs_config {
    cloudwatch_logs { group_name = aws_cloudwatch_log_group.build.name }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = <<-YAML
      version: 0.2
      phases:
        pre_build:
          commands:
            - aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY
            - TAG="s3-$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | tr -cd 'A-Za-z0-9_.')"
        build:
          commands:
            - docker build --build-arg APP_VERSION=$TAG -t $REPO_URL:$TAG .
            - docker push $REPO_URL:$TAG
        post_build:
          commands:
            - printf '[{"name":"%s","imageUri":"%s"}]' "$CONTAINER_NAME" "$REPO_URL:$TAG" > imagedefinitions.json
      artifacts:
        files:
          - imagedefinitions.json
    YAML
  }
}
data "aws_iam_policy_document" "pipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "pipeline" {
  name                 = "${var.name}-pipeline"
  path                 = "/app/"
  permissions_boundary = local.boundary
  assume_role_policy   = data.aws_iam_policy_document.pipeline_assume.json
}
data "aws_iam_policy_document" "pipeline" {
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
  statement {
    actions   = ["s3:GetBucketVersioning", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]
  }
  statement {
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [aws_codebuild_project.this.arn]
  }
  statement {
    actions   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition", "ecs:UpdateService", "ecs:TagResource"]
    resources = ["*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [var.execution_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role_policy" "pipeline" {
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}
resource "aws_codepipeline" "this" {
  name          = var.name
  pipeline_type = "V2"
  role_arn      = aws_iam_role.pipeline.arn
  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["src"]
      configuration = {
        S3Bucket             = aws_s3_bucket.artifacts.bucket
        S3ObjectKey          = local.source_key
        PollForSourceChanges = "false"
      }
    }
  }
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["src"]
      output_artifacts = ["imagedef"]
      configuration    = { ProjectName = aws_codebuild_project.this.name }
    }
  }
  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["imagedef"]
      configuration = {
        ClusterName = var.cluster_name
        ServiceName = var.service_name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}
