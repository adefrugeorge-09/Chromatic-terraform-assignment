variable "name_prefix" {
  description = "Prefix for resource names, e.g. important-api-staging."
  type        = string
}

variable "parameter_path" {
  description = "Parameter Store path prefix, e.g. /important-api/staging. No trailing slash."
  type        = string

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", var.parameter_path))
    error_message = "parameter_path must look like /segment/segment with no trailing slash."
  }
}

variable "create_kms_key" {
  description = "Create a customer-managed KMS key. When false, SecureStrings use the AWS-managed aws/ssm key."
  type        = bool
  default     = true
}

variable "kms_key_administrators" {
  description = "IAM principal ARNs granted administrative access to the key."
  type        = list(string)
  default     = []
}

variable "parameters" {
  description = "Plain (non-secret) configuration parameters, name => value. Stored as String."
  type        = map(string)
  default     = {}
}

variable "secret_parameters" {
  description = "Names of SecureString parameters to create. Values are set out of band."
  type        = list(string)
  default     = []
}
