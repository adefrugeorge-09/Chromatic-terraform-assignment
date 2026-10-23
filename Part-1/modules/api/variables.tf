variable "name_prefix" {
  description = "Prefix for resource names, e.g. important-api-staging."
  type        = string
}

variable "environment" {
  description = "Environment name, used for descriptions and log levels."
  type        = string
}

variable "stage_name" {
  description = "API Gateway stage name."
  type        = string
}

# Networking ------------------------------------------------------------------
variable "vpc_id" {
  description = "VPC the Lambda ENIs are created in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the Lambda (one per AZ)."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least one private subnet is required."
  }
}

# Lambda ----------------------------------------------------------------------
variable "lambda_source_dir" {
  description = "Directory containing the Lambda source (with node_modules installed)."
  type        = string
}

variable "lambda_runtime" {
  description = "Lambda runtime identifier."
  type        = string
  default     = "nodejs22.x"
}

variable "lambda_memory_size" {
  description = "Memory in MB."
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Timeout in seconds."
  type        = number
  default     = 10
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency (-1 = unreserved)."
  type        = number
  default     = -1
}

variable "tracing_enabled" {
  description = "Enable active X-Ray tracing (not supported by local emulators)."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention for the Lambda and API access log groups."
  type        = number
  default     = 30
}

# API Gateway -----------------------------------------------------------------
variable "throttling_burst_limit" {
  description = "Stage-level burst limit."
  type        = number
}

variable "throttling_rate_limit" {
  description = "Stage-level rate limit (req/s)."
  type        = number
}

variable "api_key_required" {
  description = "Require callers to present the Parameter Store api-key in the x-api-key header."
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "Allowed CORS origins. Empty disables CORS."
  type        = list(string)
  default     = []
}

# Secrets / config ------------------------------------------------------------
variable "parameter_path" {
  description = "Parameter Store path the function may read (no trailing slash)."
  type        = string
}

variable "parameter_arns" {
  description = "ARNs of the individual parameters under parameter_path."
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for decrypting SecureStrings and encrypting logs. Null = AWS-managed keys."
  type        = string
  default     = null
}

# Local dev -------------------------------------------------------------------
variable "local_endpoint_url" {
  description = "Local emulator endpoint, injected into the function as AWS_ENDPOINT_URL. Null on real AWS."
  type        = string
  default     = null
}
