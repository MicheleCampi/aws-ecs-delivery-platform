# Runbook: first go-live of prod

Scope: bring up prod from zero, verify it, and decide go or no-go. Version
changes after go-live follow [cutover.md](cutover.md).

## 1. Preconditions

- [ ] `main` is green: `validate` and every `plan` job pass.
- [ ] The CI plan for `envs/prod` shows only the expected adds.
- [ ] The image tag in `envs/prod/terraform.tfvars` exists in ECR and was already verified in qa (same digest).
- [ ] A cost estimate is recorded and approved, and a destroy is planned in the same session.

## 2. Apply

    gh workflow run apply.yml --ref main -f env=prod -f action=apply
    # approve the prod environment (reviewer, then 5 min wait)

Success: the job log ends with `Apply complete!` and the expected resource count.

## 3. Smoke test

    ALB=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[0].DNSName' --output text)
    curl -sk -o /dev/null -w '%{http_code}\n' https://$ALB/healthz        # 200
    aws ecs describe-services --cluster delivery-prod --services delivery-prod \
      --query 'services[0].[runningCount,deployments[0].rolloutState]'   # [2, COMPLETED]

Success: healthz 200, 2 running tasks in 2 AZ, rollout COMPLETED, image digest
equal to the one verified in qa.

## 4. Monitoring check

    aws cloudwatch describe-alarms --alarm-name-prefix delivery-prod \
      --query 'MetricAlarms[].[AlarmName,StateValue]' --output text

Success: all alarms OK (CPU may stay INSUFFICIENT_DATA for a few minutes), the
dashboard `delivery-prod` exists, and the SNS topic has the intended subscribers.

## 5. Go / no-go

| Signal | Go | No-go |
|---|---|---|
| healthz | 200 for 5 minutes | any non-200 |
| Tasks | 2 running, 2 AZ | fewer, or flapping |
| Alarms | all OK | any ALARM |
| Plan after apply | `terraform plan -detailed-exitcode` exits 0 | drift |

## 6. Rollback paths

- **Bad version:** `scripts/cutover.sh prod <previous_tag>` (measured at 174 s with no failed request, see README evidence).
- **Bad infrastructure:** `gh workflow run apply.yml --ref main -f env=prod -f action=destroy`, then check zero NAT, ALB, EIP, VPC, ECS, alarms and SNS.

## 7. Record

Run ids, start and end time, healthz counts, alarm states, cost, and the
go/no-go decision with who took it.
