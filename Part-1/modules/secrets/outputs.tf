output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key, or null if the AWS-managed key is used"
  value       = var.create_kms_key ? aws_kms_key.this[0].arn : null
}

output "parameter_path" {
  description = "Parameter Store path prefix"
  value       = var.parameter_path
}

output "parameter_arns" {
  description = "ARNs of every parameter created by this module"
  value = concat(
    [for p in aws_ssm_parameter.config : p.arn],
    [for p in aws_ssm_parameter.secret : p.arn],
  )
}

output "parameter_names" {
  description = "Full names of every parameter created by this module"
  value = concat(
    [for p in aws_ssm_parameter.config : p.name],
    [for p in aws_ssm_parameter.secret : p.name],
  )
}
