# aws-ecs-delivery-platform

Terraform for a containerised service on AWS: VPC with private subnets and NAT,
ECS Fargate behind an ALB with Cognito authentication, ECR, least-privilege IAM,
CodeBuild/CodePipeline, DEV/QA/PROD with image promotion, and a tested cut-over
and rollback runbook.

Status: designed, built and verified in a personal AWS account, evidence in CI.
Not operated in production. Every apply is followed by a destroy in the same
session; total spend is capped at 30 EUR (see docs/budget.md, added later).
