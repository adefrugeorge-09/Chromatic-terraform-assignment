# -----------------------------------------------------------------------------
# Identity / naming
# -----------------------------------------------------------------------------
variable "project" {
  description = "Short project name used as a prefix for every resource name."
  type        = string
  default     = "important-api"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project))
    error_message = "project must be lowercase alphanumeric/hyphens, 2-31 chars, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment. Drives naming, tagging and environment-specific defaults."
  type        = string

  validation {
    condition     = contains(["local", "staging", "production"], var.environment)
    error_message = "environment must be one of: local, staging, production (add new ones here and under environments/)."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "extra_tags" {
  description = "Additional tags applied to every resource (e.g. cost-centre, team)."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Local development (MiniStack)
# -----------------------------------------------------------------------------
variable "local_endpoint_url" {
  description = "Endpoint URL of the local AWS emulator (MiniStack). Leave null for real AWS environments."
  type        = string
  default     = null

  validation {
    condition     = var.local_endpoint_url == null || can(regex("^https?://", var.local_endpoint_url))
    error_message = "local_endpoint_url must be an http(s) URL."
  }
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be unique per environment if VPCs are ever peered."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (and therefore public/private subnet pairs) to use."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all private subnets (cheaper, not HA). Set false in production for one NAT gateway per AZ."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# API / Lambda
# -----------------------------------------------------------------------------
variable "api_stage_name" {
  description = "API Gateway stage name. Defaults to the environment name."
  type        = string
  default     = null
}

variable "lambda_runtime" {
  description = "Lambda runtime identifier."
  type        = string
  default     = "nodejs22.x"
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB (CPU scales with memory)."
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 10
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for the Lambda. -1 means unreserved (account pool)."
  type        = number
  default     = -1
}

variable "api_throttling_burst_limit" {
  description = "API Gateway stage burst limit (requests)."
  type        = number
  default     = 100
}

variable "api_throttling_rate_limit" {
  description = "API Gateway stage steady-state rate limit (requests/second)."
  type        = number
  default     = 50
}

variable "api_key_required" {
  description = "Require the x-api-key header (value from Parameter Store) on every request. Disable only for local development."
  type        = bool
  default     = true
}

variable "api_cors_allowed_origins" {
  description = "Origins allowed by API Gateway CORS. Empty list disables CORS configuration."
  type        = list(string)
  default     = []
}

variable "tracing_enabled" {
  description = "Enable active X-Ray tracing on the Lambda. Disable for local emulators."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention for Lambda and API Gateway access logs."
  type        = number
  default     = 30
}

variable "response_valid_period_ms" {
  description = "How long (ms) an issued asset ID is valid. Published to Parameter Store and read by the Lambda at runtime."
  type        = number
  default     = 300000
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------
variable "create_kms_key" {
  description = "Create a customer-managed KMS key for SecureString parameters and log encryption. When false the AWS-managed aws/ssm key is used (fine for local/dev)."
  type        = bool
  default     = true
}

variable "kms_key_administrators" {
  description = "IAM principal ARNs allowed to administer the KMS key (in addition to the account root). Typically the ops/platform role."
  type        = list(string)
  default     = []
}
