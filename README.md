# important-api

Terraform for a small HTTP API: **API Gateway (HTTP API) → Lambda (Node.js 22)**,
running in private subnets of a dedicated VPC, with configuration and secrets
delivered through **SSM Parameter Store** under a **least-privilege** execution role.

- Part I (this README): production-ready, multi-environment Terraform.
- Part II: [`docs/ECS-MIGRATION.md`](docs/ECS-MIGRATION.md) — how the approach
  changes when the API moves from API Gateway to ECS.

## Layout

```
.
├── main.tf                  # composes the three modules below
├── variables.tf / locals.tf / outputs.tf
├── providers.tf             # one provider block for every env (MiniStack-aware)
├── backend.tf               # S3 remote state, configured per env at init
├── environments/
│   ├── local.tfvars         # MiniStack
│   ├── staging.tfvars  + staging.s3.tfbackend
│   └── production.tfvars + production.s3.tfbackend
├── modules/
│   ├── network/             # VPC/subnets/NAT  (wraps terraform-aws-modules/vpc)
│   ├── secrets/             # KMS key + Parameter Store entries
│   └── api/                 # Lambda (wraps terraform-aws-modules/lambda) + HTTP API
├── code/                    # Lambda source + unit tests
├── docs/ECS-MIGRATION.md    # Part II write-up
├── .github/workflows/       # CI: checks, plan-per-env on PR, apply on main
└── Makefile                 # the same commands humans and CI run
```

## Environments

One root module, one `tfvars` file and one state file per environment. There
is no `count = var.env == "prod" ? ...` branching anywhere: every difference
between environments is a variable with a sensible default, overridden in
`environments/<env>.tfvars`.

| | local | staging | production |
|---|---|---|---|
| Target | MiniStack (Docker) | AWS | AWS |
| State | local file | S3 `…-staging` | S3 `…-production` |
| AZs / NAT | 2 / shared | 2 / shared | 3 / one per AZ |
| KMS | AWS-managed | customer-managed | customer-managed |
| Lambda | 256 MB | 256 MB | 512 MB, reserved concurrency |
| Log retention | 1 day | 14 days | 90 days |

Separate state files (not workspaces) keep a mistake in staging physically
unable to touch production, and let each environment live in its own AWS
account with its own CI role. Adding a `dev` environment is a new pair of
files under `environments/`.

### Why not Terraform workspaces?

Workspaces share one backend and one set of credentials, which fights the
one-account-per-environment model and makes "which environment am I in?"
a runtime question. File-per-environment makes it a `git diff`.

## Local development

Requirements: Docker, Node 22, Terraform 1.15 (`.tool-versions` works with
`asdf`/`mise`), `make`.

```bash
docker compose up -d                 # MiniStack on :4566
make deps                            # npm ci for the Lambda
make plan ENV=local && make apply ENV=local
curl "$(terraform output -raw api_url)/"
```

`ENV=local` initialises Terraform with `-backend=false` (state in the working
directory) and sets `local_endpoint_url`, which flips the provider into
emulator mode and injects `AWS_ENDPOINT_URL` into the Lambda so its SDK calls
land in MiniStack too. The KMS CMK and X-Ray are off locally
(`create_kms_key = false`, `tracing_enabled = false`) because emulator support
for them varies; everything else is identical to the cloud environments.

Run the Lambda's unit tests with `make test` (no AWS or Docker needed).

## Deploying to AWS

```bash
make plan  ENV=staging      # init with environments/staging.s3.tfbackend, then plan
make apply ENV=staging      # applies the saved plan file only
```

In practice nobody runs `apply` from a laptop: CI plans each environment on
every PR and posts the plan as a comment, applies `staging` on merge to
`main`, and applies `production` after a reviewer approves the GitHub
Environment deployment. CI authenticates with OIDC (`vars.AWS_ROLE_ARN` per
GitHub Environment: `staging-plan` / `production-plan` hold read-only roles
for PR plans, `staging` / `production` hold deploy roles), so there are no
long-lived AWS keys anywhere. The apply job re-plans on `main` instead of
reusing the PR's plan file, since that plan was made against a different
base commit.

### First-time setup per environment

1. Create the state bucket named in `environments/<env>.s3.tfbackend`
   (versioning + SSE on; locking uses S3 conditional writes, no DynamoDB).
2. Create the CI OIDC roles (read-only for plans, deploy for applies) and
   put their ARNs in the `AWS_ROLE_ARN` variable of the `<env>-plan` and
   `<env>` GitHub Environments.
3. `make apply ENV=<env>` once from a privileged session, then set the real
   secret values (see below).

## Secrets and configuration

All runtime configuration lives under `/<project>/<environment>/` in Parameter
Store. Plain settings (`response-valid-period-ms`) are managed in tfvars.
Secrets (`api-key`, checked against the `x-api-key` header on every request
outside local dev) are **created** by Terraform as `SecureString` with a
write-only placeholder and **never** have their value in git, state or plan
output; operators set them out of band:

```bash
aws ssm put-parameter --name /important-api/production/api-key \
  --type SecureString --overwrite --key-id alias/important-api-production-secrets \
  --value "$(op read op://infra/important-api-prod/api-key)"
```

The Lambda reads the whole path once per container (`GetParametersByPath`),
caches it for 60 s, and keeps serving the last good values if SSM blips.
Details in [`modules/secrets/README.md`](modules/secrets/README.md).

## Least-privilege IAM

The original PoC attached `AWSLambdaBasicExecutionRole` and
`AWSLambdaVPCAccessExecutionRole`. Both are gone. The execution role now has
exactly:

| Statement | Actions | Resource |
|---|---|---|
| logs | `CreateLogStream`, `PutLogEvents` | this function's log group only |
| network | `ec2:*NetworkInterface*` | `*` (ENI actions are not resource-scopable) |
| config | `ssm:GetParameter`, `GetParameters`, `GetParametersByPath` | `/<project>/<env>` path only |
| decrypt | `kms:Decrypt` | the environment's key, only via SSM (`kms:ViaService`) |
| tracing | X-Ray put segments | `*` (prod/staging only) |

Only this API (any stage/route) may invoke the function (`lambda:InvokeFunction`
with `source_arn` scoped to the API's execution ARN). The function's security
group allows **no ingress** and egress on 443 only, and the VPC's default
security group is locked to deny-all.

## Other changes from the PoC

- Lambda spans every private subnet instead of one; NAT is per-AZ in production.
- Structured JSON logging with retention and KMS encryption; API Gateway access
  logs in their own group; stage throttling and optional CORS are variables.
- Hard-coded `staging-*` names and tags replaced by `<project>-<environment>`
  naming via `locals` and provider `default_tags`.
- Unused `aws_ami` lookup and the misuse of `aws_default_security_group` removed.
- Lambda code fails closed (503) if configuration is unavailable, and has unit tests.

## Working on this repo

- After the first `terraform init` with registry access, commit the generated
  `.terraform.lock.hcl` (`terraform providers lock -platform=linux_amd64
  -platform=darwin_arm64`) so every machine and CI resolve identical provider
  builds.
- `pre-commit install` once; it runs fmt, validate, tflint, trivy and secret scanning.
- `make fmt lint validate test` is what CI runs; run it before pushing.
- Reviews are routed by `.github/CODEOWNERS`; `main` should require a passing
  `checks` job and one approval. `modules/secrets` and production files also
  page the security / SRE owners (CODEOWNERS requires one of the listed owners;
  add a second required approval in branch protection if both must sign off).
- Pin upstream module versions with `~>` minor constraints and bump them in
  dedicated PRs so the plan diff is only the upgrade.

## Future work

- VPC interface endpoints for SSM/KMS/Logs so the Lambda needs no NAT at all.
- `terraform test` suite with mocked providers for the modules.
- Custom domain + WAF on the API; alarms on 5xx / p99 latency (see Part II for
  the monitoring approach).
