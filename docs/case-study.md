# Case study: delivering a containerised service on AWS with a measured cut-over

**Problem.** Ship a containerised service to AWS across DEV, QA and PROD so that
a new version can go live, and be rolled back, without dropping user requests.

**Constraints.** Personal AWS account, total spend capped at 30 EUR, every apply
destroyed in the same session. Designed, built and verified; not operated in
production.

**What I built.**
- Terraform for VPC, private subnets and NAT (one per AZ in prod), ECS Fargate
  behind an ALB with Cognito authentication, ECR with immutable tags,
  least-privilege IAM, CloudWatch alarms to SNS.
- CodeBuild/CodePipeline builds the dev image; QA and PROD promote that exact
  image by tag, so what was tested is what runs.
- GitHub Actions: plan on every PR, apply only by manual dispatch through OIDC
  with an environment approval (PROD adds a 5 minute wait).
- [Go-live](runbooks/go-live.md) and [cut-over and rollback](runbooks/cutover.md) runbooks.

**Measured results** (details in the [README evidence table](../README.md#evidence)).

| What | Result |
|---|---|
| Cut-over to a new version under a 2 s probe (A-012) | 158 s, 83/83 requests 200 |
| Rollback to the previous version (A-012) | 174 s, 91/91 requests 200 |
| One prod task stopped on purpose (A-011) | 60/60 requests 200 |
| Health check broken on purpose (A-013) | ALARM after ~4 min, OK ~4 min after restore, SNS both ways |
| IAM permission boundary (A-014) | 9/9 policy simulator checks as expected |
| ARM64 vs x86 at 300 rps (A-015) | Same latency, about 41% less task CPU |
| QA promotion (A-010) | Same image digest as dev |

**What is not covered.** No production traffic or real users; Container
Insights is off to keep cost near zero; the ARM price advantage comes from the
list price and is not measured.
