# Part II — Moving the API from API Gateway + Lambda to ECS

**Context.** The Part I design has run in production for several months.
API Gateway has become too expensive and too constraining, and leadership has
approved moving the API application to Amazon ECS. This document describes
how the Terraform and the surrounding workflow change. Code snippets are
illustrative; nothing in this repo has been changed for Part II.

## 1. Target architecture

```
Internet ──► ALB (public subnets, ACM cert, WAF)
                 │  target group, /healthz checks
                 ▼
         ECS Fargate service (private subnets, 2–3 AZs)
                 │  task role: ssm:GetParameter* on /important-api/<env>, kms:Decrypt
                 ▼
         SSM Parameter Store  ·  CloudWatch Logs  ·  X-Ray / OTel collector sidecar
```

Fargate rather than EC2 capacity: the service is small, bursty and stateless,
so paying for idle instances buys nothing, and Fargate removes AMI patching
and cluster capacity management from the team. Fargate Spot is used for a
share of capacity in non-production.

Most of Part I survives unchanged, which is the point of having modularised it:

| Part I piece | Part II |
|---|---|
| `modules/network` | unchanged (public subnets finally get used — by the ALB) |
| `modules/secrets` | unchanged; the ECS *task role* gets the same scoped statements the Lambda role had |
| `modules/api` | **replaced** by `modules/service` (ALB + ECS) and `modules/ecr` |
| `code/` | gains a `Dockerfile`; `config.mjs` is reused as-is, `index.mjs` becomes an HTTP server |
| `environments/*.tfvars` | new variables (task size, min/max count, image tag); API Gateway ones removed |
| CI | gains build-and-push of the image; apply step passes the new image tag |

The Lambda handler already used the HTTP API v2 payload shape through a thin
`json()` helper, so the application change is wrapping the same logic in a
small HTTP server (Node's `http` or Fastify) with a `/healthz` route.
Configuration loading via Parameter Store is unchanged: `getConfig()` runs at
startup and then refreshes on its TTL, exactly as before.

## 2. Environment setup

**Module shape.** `modules/service` owns: the ECS cluster (Container Insights
on), task definition, service, ALB + listener + target group, security
groups, IAM task/execution roles, CloudWatch log group, autoscaling target
and policies, and the alarms in §3. It takes `image` (an immutable
`<ecr-repo>@sha256:…` digest, never `latest`), `cpu`/`memory`,
`min_count`/`max_count`, and `environment` as inputs. `modules/ecr` owns the
repository with image scanning on push and a lifecycle policy keeping the
last N images.

**Security groups** follow the same deny-by-default pattern as Part I: the
ALB SG allows 443 from the internet (80 only to redirect), the task SG allows
the container port from the ALB SG only, egress 443 only. With the Lambda
gone, the NAT gateways are replaced by VPC interface endpoints for ECR, Logs,
SSM and KMS — cheaper, and the tasks never touch the public internet.

**Secrets** are injected by ECS at task start using the task definition's
`secrets` block, so the container reads them from the environment and the
execution role (not the task role) is granted read on the path:

```hcl
container_definitions = jsonencode([{
  name  = "api"
  image = var.image
  secrets = [
    { name = "API_KEY", valueFrom = "${module.secrets.parameter_path}/api-key" },
  ]
  environment = [
    { name = "CONFIG_PARAMETER_PATH", value = module.secrets.parameter_path },
  ]
  healthCheck = { command = ["CMD-SHELL", "curl -sf http://localhost:8080/healthz || exit 1"], interval = 15, retries = 3 }
  logConfiguration = { logDriver = "awslogs", options = { awslogs-group = aws_cloudwatch_log_group.api.name, awslogs-region = var.region, awslogs-stream-prefix = "api" } }
}])
```

**Per-environment differences** stay in tfvars, e.g.

| | staging | production |
|---|---|---|
| Task size | 0.25 vCPU / 512 MB | 0.5 vCPU / 1 GB |
| min / max tasks | 1 / 4 (Fargate Spot 100 %) | 3 / 30 (one per AZ minimum, Spot ≤ 50 %) |
| Deployment | rolling, 100/200 | rolling with circuit breaker + rollback; blue/green via CodeDeploy if we need instant rollback |
| ALB | internal-ish (allow-listed CIDRs) | public, WAF managed rule set, ACM cert |

**State and migration.** Both stacks run side by side in the same root module
for one release: add `module.service`, put a custom domain on the existing API Gateway
(a small prerequisite PR; Part I still uses the default execute-api URL),
point a weighted Route 53 record at the ALB alongside it, shift traffic 10 → 50 → 100 %
over a few days while watching §3 dashboards, then delete `module.api` in a
follow-up PR. No state surgery needed because the new resources have new
addresses; the removal PR's plan is purely destroys.

## 3. Monitoring and alerting

Container Insights plus ALB metrics give almost everything without
instrumentation. Each alarm goes to an SNS topic → PagerDuty (production) or
Slack (staging), and all of them are defined in `modules/service` so an
environment cannot exist without its alarms.

| Signal | Metric | Page? |
|---|---|---|
| Availability | ALB `HTTPCode_Target_5XX_Count` / `RequestCount` > 2 % for 5 min | yes |
| Latency | ALB `TargetResponseTime` p99 > 1 s for 10 min | yes |
| Capacity | `RunningTaskCount` < `min_count`; `UnHealthyHostCount` > 0 for 5 min | yes |
| Saturation | service `CPUUtilization` or `MemoryUtilization` > 85 % for 15 min | warn (autoscaling should prevent) |
| Deploys | ECS deployment circuit breaker tripped (EventBridge rule) | yes |
| Dependencies | app-emitted `ConfigRefreshFailed` > 0 for 15 min | warn |
| Cost / abuse | WAF blocked requests spike; `RequestCount` > 3× 7-day baseline (anomaly detection) | warn |

Application logs stay structured JSON (`awslogs` driver → CloudWatch Logs,
same retention and KMS settings as Part I), and the app emits a few custom
metrics through the Embedded Metric Format so no agent is needed. Traces go
through an AWS OTel collector sidecar to X-Ray. A single CloudWatch dashboard
per environment shows the four golden signals next to task count and the
autoscaling target, so an on-call engineer can see *why* a scale event
happened.

## 4. Metrics and autoscaling

Usage is weekday-business-hours across time zones, peaking during the North
American workday, with occasional unexpected spikes. Three layers handle this:

1. **Scheduled scaling for the predictable shape.** Application Auto Scaling
   scheduled actions raise `min_capacity` ahead of the ramp and lower it
   after. Schedules are in UTC; the one-hour DST drift is harmless because
   the floor is raised 30 minutes early and target tracking covers the rest:

   ```hcl
   resource "aws_appautoscaling_scheduled_action" "na_workday_start" {
     name               = "${local.name}-na-workday"
     service_namespace  = "ecs"
     resource_id        = "service/${cluster}/${service}"
     scalable_dimension = "ecs:service:DesiredCount"
     schedule           = "cron(30 12 ? * MON-FRI *)"   # 08:30 ET
     scalable_target_action {
       min_capacity = var.workday_min_count
       max_capacity = var.max_count
     }
   }
   # ...and a matching action at 02:00 UTC dropping to var.min_count,
   # plus a smaller morning bump for EMEA hours.
   ```

   Pre-warming the floor means the North American ramp never waits on
   reactive scaling, and nights/weekends run at the 1-per-AZ floor.

2. **Target tracking for the unexpected.** Two target-tracking policies run
   at all times: `ALBRequestCountPerTarget` (the leading indicator — requests
   arrive before CPU rises) with a target derived from load testing, and
   `ECSServiceAverageCPUUtilization` at 60 % as a backstop. Scale-out
   cooldown is short (60 s), scale-in long (300 s) so a spike does not cause
   flapping. Because tasks are Fargate, a scale-out is ~45–60 s from alarm
   to in-service; the ALB target group deregistration delay is set to 15 s so
   scale-in is quick too.

3. **Guardrails.** `max_count` is a hard ceiling per environment to bound cost
   from a runaway spike or abuse; WAF rate-based rules shed obviously
   malicious traffic before it reaches the service; and an alarm fires when
   the service sits at `max_count` for more than 10 minutes, since that means
   the ceiling, not the application, is now the bottleneck.

The autoscaling and ALB metrics above are also what the §3 dashboard shows,
so the two sections share the same numbers.

## 5. Local development workflow

Part I needed Terraform + MiniStack just to run the function. With a
container, the inner loop gets simpler:

```bash
docker compose up        # api + ministack (SSM only, seeded with /important-api/local/*)
curl localhost:8080/
```

`docker-compose.yml` runs the same image CI builds, with `AWS_ENDPOINT_URL`
pointing at MiniStack for Parameter Store and hot reload via a bind mount of
`code/`. `npm test` keeps running unit tests with the injected config loader
from Part I. Terraform against MiniStack remains possible for the
network/secrets modules, but ECS/ALB are not something an emulator represents
faithfully, so the Terraform side is exercised against a shared `dev` AWS
environment (an extra `environments/dev.tfvars`) rather than locally.
Engineers get `terraform plan` locally via the same read-only OIDC role CI
uses for plans.

## 6. CI

The Part I pipeline keeps its shape (checks → plan per env on PR → apply
staging on merge → gated apply to production) and gains an image stage:

```
PR:    lint/validate/tflint/trivy  ─┐
       npm test                     ├─► build image ─► trivy image scan ─► plan (staging, prod) with image=<pr digest>
main:  build + push to ECR (tag = git sha, immutable) ─► apply staging ─► smoke test ─► [approval] ─► apply production
```

Points worth calling out:

- The image digest is passed to Terraform as `-var image=…`, so the task
  definition is a normal Terraform change and the plan shows exactly which
  image is going where. No `latest`, no out-of-band `aws ecs update-service`.
- The ECR push and the ECS apply use different OIDC roles: the build role can
  only push to one repository; the deploy roles are the Part I per-environment
  roles with ECS/ALB permissions added.
- The smoke test after each apply hits the ALB through the public DNS name
  and checks both `/` and `/healthz`; a failure blocks the production job.
  The ECS deployment circuit breaker provides automatic rollback inside AWS
  if the new tasks never become healthy.
- Dependabot/Renovate keeps the base image, Node dependencies and Terraform
  module versions moving in small, separately reviewable PRs.

## Summary

The migration swaps one module (`api` → `service` + `ecr`), adds a Dockerfile
and a health endpoint, and leaves networking, secrets, IAM scoping, environment
layout and most of CI intact. Scheduled scaling absorbs the known weekday
shape; target tracking on request count absorbs the surprises; alarms and a
per-environment dashboard make both visible; and immutable image digests
flowing through Terraform keep deploys reviewable and reversible.
