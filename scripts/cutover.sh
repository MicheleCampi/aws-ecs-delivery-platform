#!/usr/bin/env bash
# Version cut-over (and rollback) of an ECS service to an immutable ECR tag.
# Terraform ignores task_definition on the service (D-0115), so releases
# happen here. Usage: scripts/cutover.sh <env> <image_tag>
set -euo pipefail
env="${1:?env}"; tag="${2:?image_tag}"
export AWS_REGION="${AWS_REGION:-eu-west-1}"
cluster="delivery-${env}"; service="delivery-${env}"; repo_name="delivery-app"

aws ecr describe-images --repository-name "$repo_name" --image-ids "imageTag=${tag}" \
  --query 'imageDetails[0].imageDigest' --output text
repo_uri=$(aws ecr describe-repositories --repository-names "$repo_name" \
  --query 'repositories[0].repositoryUri' --output text)
current=$(aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].taskDefinition' --output text)

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
aws ecs describe-task-definition --task-definition "$current" \
  --query taskDefinition > "$tmp/current.json"
python3 -I - "$tmp/current.json" "$tmp/next.json" "${repo_uri}:${tag}" <<'PY'
import json, sys
src, dst, image = sys.argv[1:4]
td = json.load(open(src))
td["containerDefinitions"][0]["image"] = image
keep = ["family", "taskRoleArn", "executionRoleArn", "networkMode",
        "containerDefinitions", "volumes", "requiresCompatibilities",
        "cpu", "memory", "runtimePlatform"]
json.dump({k: td[k] for k in keep if td.get(k) is not None}, open(dst, "w"))
PY
next=$(aws ecs register-task-definition --cli-input-json "file://$tmp/next.json" \
  --query taskDefinition.taskDefinitionArn --output text)
echo "cutover ${service}: ${current##*/} -> ${next##*/} (${tag})"

aws ecs update-service --cluster "$cluster" --service "$service" \
  --task-definition "$next" --query 'service.deployments[0].id' --output text
aws ecs wait services-stable --cluster "$cluster" --services "$service"
aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].deployments[0].[rolloutState,taskDefinition,runningCount]' --output text
