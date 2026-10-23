# secrets module

Creates the KMS key and SSM Parameter Store entries the application reads at
runtime, under one path per deployment (`/<project>/<environment>/...`).

| Input               | Stored as      | Value managed by                          |
|---------------------|----------------|-------------------------------------------|
| `parameters`        | `String`       | Terraform (tfvars)                        |
| `secret_parameters` | `SecureString` | Operators / rotation job, **not** Terraform |

## Why secrets are not managed by Terraform

Anything passed into a normal `aws_ssm_parameter.value` ends up in plain text
in the state file and in plan output. Instead the module uses the provider's
write-only `value_wo` attribute to create the parameter with a placeholder
that is never persisted, and leaves the real value to be set out of band:

```bash
aws ssm put-parameter \
  --name /important-api/production/api-key \
  --type SecureString --overwrite \
  --key-id alias/important-api-production-secrets \
  --value "$(op read 'op://infra/important-api-prod/api-key')"
```

Terraform still owns the parameter's existence, its KMS key and the IAM policy
that lets the Lambda read it, so a `destroy` or environment rebuild recreates
everything except the secret material itself, which is exactly what we want.

## Consuming parameters

The `api` module grants the Lambda `ssm:GetParameter*` on this path only and
`kms:Decrypt` on this key only. The Lambda loads parameters once per container
with `GetParametersByPath` and caches them (see `code/config.mjs`).
