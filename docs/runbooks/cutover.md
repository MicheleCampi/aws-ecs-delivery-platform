# Runbook: version cut-over and rollback (ECS)

Releases change the image of a running service; Terraform owns the
infrastructure and ignores `task_definition` on the service (D-0115).

## Preconditions
- The tag exists in ECR (tags are immutable) and passed dev and qa.
- The service is stable: `aws ecs describe-services` shows one deployment, COMPLETED.
- A probe is running: `curl -sk https://<alb>/healthz` every 2 s.

## Cut-over
    scripts/cutover.sh prod <new_tag>
ECS starts new tasks (max 200%), waits for ALB health (2 x 10 s), then drains
old tasks (deregistration delay 5 s). The circuit breaker rolls back
automatically if new tasks fail to become healthy.

## Rollback
    scripts/cutover.sh prod <previous_tag>
Same mechanism, same guarantees. The previous tag is the one printed as
the source of the last cut-over.

## Evidence to record
Probe counts (ok/bad) per phase, rolloutState COMPLETED, task definition
revisions before and after (D-0120, A-012).
