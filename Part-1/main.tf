# Root module: composes the environment from three local modules.
#
#   network  -> VPC, subnets, NAT (wraps terraform-aws-modules/vpc)
#   secrets  -> KMS key + Parameter Store entries the application reads
#   api      -> Lambda (wraps terraform-aws-modules/lambda) + HTTP API Gateway
#
# Environment-specific values come from environments/<env>.tfvars; nothing in
# this file should need to change between environments.

module "network" {
  source = "./modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}

module "secrets" {
  source = "./modules/secrets"

  name_prefix            = local.name_prefix
  parameter_path         = local.parameter_path
  create_kms_key         = var.create_kms_key
  kms_key_administrators = var.kms_key_administrators

  # Non-secret runtime configuration, versioned with the infrastructure.
  parameters = {
    "response-valid-period-ms" = tostring(var.response_valid_period_ms)
  }

  # Secret values are NOT managed by Terraform. Terraform creates the
  # parameter with a placeholder (write-only, never persisted in state) and
  # operators rotate the real value out of band. See modules/secrets/README.md.
  secret_parameters = ["api-key"]
}

module "api" {
  source = "./modules/api"

  name_prefix = local.name_prefix
  environment = var.environment
  stage_name  = local.api_stage_name

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  lambda_source_dir           = "${path.module}/code"
  lambda_runtime              = var.lambda_runtime
  lambda_memory_size          = var.lambda_memory_size
  lambda_timeout              = var.lambda_timeout
  lambda_reserved_concurrency = var.lambda_reserved_concurrency
  tracing_enabled             = var.tracing_enabled

  throttling_burst_limit = var.api_throttling_burst_limit
  throttling_rate_limit  = var.api_throttling_rate_limit
  cors_allowed_origins   = var.api_cors_allowed_origins
  api_key_required       = var.api_key_required
  log_retention_days     = var.log_retention_days

  # Least-privilege wiring: the Lambda may only read parameters under this
  # path and decrypt with this key.
  parameter_path = local.parameter_path
  parameter_arns = module.secrets.parameter_arns
  kms_key_arn    = module.secrets.kms_key_arn

  # The Lambda runtime inside MiniStack needs to be told where "AWS" is.
  local_endpoint_url = var.local_endpoint_url
}
