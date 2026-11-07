#!/usr/bin/env bash
# A-014: evaluate the deployed app-boundary with the IAM policy simulator.
# The simulated identity policy allows everything, so only the boundary limits it.
# Free (simulation only, nothing is created). Exit 1 on any mismatch.
set -euo pipefail
acc=$(aws sts get-caller-identity --query Account --output text)
arn="arn:aws:iam::${acc}:policy/app-boundary"
ver=$(aws iam get-policy --policy-arn "$arn" --query Policy.DefaultVersionId --output text)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
aws iam get-policy-version --policy-arn "$arn" --version-id "$ver" --query PolicyVersion.Document > "$tmp/boundary.json"
echo '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' > "$tmp/admin.json"
jq -n --rawfile a "$tmp/admin.json" --rawfile b "$tmp/boundary.json" \
  '{PolicyInputList:[$a], PermissionsBoundaryPolicyInputList:[$b]}' > "$tmp/base.json"
fail=0
sim() { # action resource passed_service expected
  local ctx=(); [ -n "$3" ] && ctx=(--context-entries "ContextKeyName=iam:PassedToService,ContextKeyValues=$3,ContextKeyType=string")
  local got; got=$(aws iam simulate-custom-policy --cli-input-json "file://$tmp/base.json" \
    --action-names "$1" --resource-arns "$2" "${ctx[@]}" --query 'EvaluationResults[0].EvalDecision' --output text)
  local res=OK; [ "$got" = "$4" ] || { res=MISMATCH; fail=1; }
  printf '%-32s %-74s %-24s %-13s %s\n' "$1" "${2//$acc/ACCOUNT}" "${3:--}" "$got" "$res"
}
echo "boundary ${arn//$acc/ACCOUNT} version ${ver}"
sim ecs:UpdateService "arn:aws:ecs:eu-west-1:${acc}:service/delivery-dev/delivery-dev" "" allowed
sim iam:PassRole "arn:aws:iam::${acc}:role/app/delivery-dev-execution" ecs-tasks.amazonaws.com allowed
sim iam:PassRole "arn:aws:iam::${acc}:role/app/delivery-dev-execution" ec2.amazonaws.com explicitDeny
sim iam:PassRole "arn:aws:iam::${acc}:role/gha-apply" ecs-tasks.amazonaws.com explicitDeny
sim iam:CreateUser "arn:aws:iam::${acc}:user/backdoor" "" explicitDeny
sim iam:AttachRolePolicy "arn:aws:iam::${acc}:role/app/delivery-dev-execution" "" explicitDeny
sim s3:GetObject "arn:aws:s3:::michele-tfstate-aws-ecs-delivery/env/prod/terraform.tfstate" "" explicitDeny
sim organizations:LeaveOrganization "*" "" explicitDeny
sim sts:AssumeRoleWithWebIdentity "arn:aws:iam::${acc}:role/gha-apply" "" explicitDeny
exit "$fail"
