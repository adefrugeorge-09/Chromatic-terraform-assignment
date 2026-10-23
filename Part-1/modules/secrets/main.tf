# Secrets & configuration for the application, delivered via SSM Parameter
# Store under a single path (e.g. /important-api/production/...).
#
# Two kinds of parameters are managed here:
#
#   parameters         - plain configuration values. Their values live in
#                        tfvars and are versioned with the infrastructure.
#   secret_parameters  - SecureString values encrypted with a KMS key. Terraform
#                        only *creates* them, using a write-only placeholder
#                        that is never stored in state or plan output. The real
#                        value is set by an operator / CI secret rotation job:
#
#     aws ssm put-parameter --name /important-api/production/api-key \
#        --type SecureString --overwrite --value "$(pass show important-api/prod/api-key)"
#
# This keeps secret material out of git, out of Terraform state and out of CI
# logs, while still letting Terraform own the parameter's existence, key and
# IAM wiring.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region
}

# -----------------------------------------------------------------------------
# KMS key (customer managed) for SecureString parameters
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "kms" {
  count = var.create_kms_key ? 1 : 0

  # Account root keeps full control so the key can never be orphaned, and so
  # IAM policies (e.g. the Lambda role's kms:Decrypt) are honoured.
  statement {
    sid       = "EnableRootAndIamPolicies"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(var.kms_key_administrators) > 0 ? [1] : []
    content {
      sid = "KeyAdministrators"
      actions = [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
        "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
        "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.kms_key_administrators
      }
    }
  }

  # CloudWatch Logs encrypts this deployment's log groups with the same key.
  statement {
    sid       = "AllowCloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${data.aws_caller_identity.current.account_id}:log-group:*${var.name_prefix}*"]
    }
  }

  # Let SSM use the key on behalf of callers in this account only.
  statement {
    sid       = "AllowSsmViaService"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "this" {
  count = var.create_kms_key ? 1 : 0

  description             = "${var.name_prefix}: application secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms[0].json

  tags = { Name = "${var.name_prefix}-secrets" }
}

resource "aws_kms_alias" "this" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.this[0].key_id
}

# -----------------------------------------------------------------------------
# Plain configuration parameters
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "config" {
  for_each = var.parameters

  name  = "${var.parameter_path}/${each.key}"
  type  = "String"
  value = each.value
  tier  = "Standard"

  tags = { Name = "${var.name_prefix}-${each.key}" }
}

# -----------------------------------------------------------------------------
# Secret parameters (SecureString, value managed out of band)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "secret" {
  for_each = toset(var.secret_parameters)

  name   = "${var.parameter_path}/${each.key}"
  type   = "SecureString"
  key_id = var.create_kms_key ? aws_kms_key.this[0].arn : null # null -> alias/aws/ssm
  tier   = "Standard"

  # Write-only: the placeholder is sent on create and never read back into
  # state. Bumping value_wo_version would re-send the placeholder, so it is
  # left at 1 and real values are rotated with `aws ssm put-parameter`.
  value_wo         = "CHANGEME-set-with-aws-ssm-put-parameter"
  value_wo_version = 1

  # Any in-place update would re-send the placeholder, so never let drift on
  # key_id (e.g. a rotation that forgot --key-id) trigger one.
  lifecycle {
    ignore_changes = [key_id]
  }

  tags = { Name = "${var.name_prefix}-${each.key}" }
}
