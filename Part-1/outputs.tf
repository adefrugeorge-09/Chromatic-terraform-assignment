output "vpc_id" {
  description = "ID of the VPC"
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.network.public_subnet_ids
}

output "api_id" {
  description = "ID of the HTTP API"
  value       = module.api.api_id
}

output "api_url" {
  description = "Invoke URL of the API stage"
  value = local.is_local ? format(
    "%s/_aws/execute-api/%s/%s",
    var.local_endpoint_url, module.api.api_id, local.api_stage_name
  ) : module.api.stage_invoke_url
}

output "lambda_function_name" {
  description = "Name of the API Lambda function"
  value       = module.api.lambda_function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.api.lambda_role_arn
}

output "parameter_path" {
  description = "Parameter Store path the application reads its configuration from"
  value       = local.parameter_path
}

output "kms_key_arn" {
  description = "ARN of the KMS key protecting secrets (null when using the AWS-managed key)"
  value       = module.secrets.kms_key_arn
}
