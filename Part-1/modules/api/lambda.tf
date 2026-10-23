# The API application: a Node.js Lambda packaged from ./code and wrapped with
# the community Lambda module (handles role, log group, permissions and all
# the boilerplate the original PoC hand-rolled).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  function_name = "${var.name_prefix}-api"

  # ARN of the Parameter Store path prefix (needed for GetParametersByPath).
  parameter_path_arn = format(
    "arn:%s:ssm:%s:%s:parameter%s",
    data.aws_partition.current.partition,
    data.aws_region.current.region,
    data.aws_caller_identity.current.account_id,
    var.parameter_path,
  )
}

# -----------------------------------------------------------------------------
# Package
# -----------------------------------------------------------------------------
# `npm ci --omit=dev` must have been run in the source directory first; CI does
# this before plan/apply (see .github/workflows). Packaging here instead of via
# the module's built-in builder avoids a Python dependency on dev machines.
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.root}/build/${local.function_name}.zip"
  excludes    = ["package-lock.json", ".DS_Store", "*.test.mjs"]
}

# -----------------------------------------------------------------------------
# Security group: the function only ever makes outbound HTTPS calls (SSM via
# the NAT gateway). No ingress at all.
# -----------------------------------------------------------------------------
resource "aws_security_group" "lambda" {
  name        = "${local.function_name}-sg"
  description = "Egress-only security group for the ${local.function_name} Lambda"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.function_name}-sg" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to AWS APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# -----------------------------------------------------------------------------
# Function
# -----------------------------------------------------------------------------
module "lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.0"

  function_name = local.function_name
  description   = "${var.environment}: issues short-lived asset IDs"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  architectures = ["arm64"]

  memory_size                    = var.lambda_memory_size
  timeout                        = var.lambda_timeout
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  publish                = true # required for allowed_triggers (permissions on $LATEST are rejected)
  create_package         = false
  local_existing_package = data.archive_file.lambda.output_path

  # Networking
  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.lambda.id]
  attach_network_policy  = true # ENI create/describe/delete; cannot be resource-scoped

  environment_variables = merge(
    {
      NODE_OPTIONS          = "--enable-source-maps"
      CONFIG_PARAMETER_PATH = var.parameter_path
      CONFIG_CACHE_TTL_MS   = "60000"
      ENVIRONMENT           = var.environment
      REQUIRE_API_KEY       = var.api_key_required ? "true" : "false"
    },
    # Point the AWS SDK inside the function at the emulator when running locally.
    var.local_endpoint_url == null ? {} : { AWS_ENDPOINT_URL = var.local_endpoint_url },
  )

  # Logging: structured JSON, scoped log group with retention.
  logging_log_format                 = "JSON"
  logging_application_log_level      = var.environment == "production" ? "INFO" : "DEBUG"
  logging_system_log_level           = "WARN"
  cloudwatch_logs_retention_in_days  = var.log_retention_days
  cloudwatch_logs_kms_key_id         = var.kms_key_arn
  attach_cloudwatch_logs_policy      = true  # scoped to this function's log group by the module
  attach_create_log_group_permission = false # the module creates the group; the function must not

  tracing_mode          = var.tracing_enabled ? "Active" : "PassThrough"
  attach_tracing_policy = var.tracing_enabled

  # ---------------------------------------------------------------------------
  # Least-privilege IAM. No AWS managed policies: every statement below is
  # scoped to the exact resources this function touches.
  # ---------------------------------------------------------------------------
  role_name        = "${local.function_name}-role"
  role_description = "Execution role for ${local.function_name}"

  attach_policy_statements = true
  policy_statements = merge(
    {
      read_parameters = {
        effect = "Allow"
        actions = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
        ]
        resources = concat([local.parameter_path_arn, "${local.parameter_path_arn}/*"], var.parameter_arns)
      }
    },
    var.kms_key_arn == null ? {} : {
      decrypt_parameters = {
        effect    = "Allow"
        actions   = ["kms:Decrypt"]
        resources = [var.kms_key_arn]
        condition = {
          via_ssm = {
            test     = "StringEquals"
            variable = "kms:ViaService"
            values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
          }
        }
      }
    },
  )

  # Only this API, on any stage/route, may invoke the function.
  allowed_triggers = {
    api_gateway = {
      service    = "apigateway"
      source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
    }
  }

  tags = { Name = local.function_name }
}
