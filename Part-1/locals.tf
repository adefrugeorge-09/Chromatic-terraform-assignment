locals {
  is_local = var.local_endpoint_url != null

  # "<project>-<environment>" is the prefix for every named resource, e.g.
  # important-api-production-vpc. Modules receive name_prefix rather than
  # composing their own so naming stays consistent in one place.
  name_prefix = "${var.project}-${var.environment}"

  api_stage_name = coalesce(var.api_stage_name, var.environment)

  # Parameter Store namespace for this deployment. The Lambda is only granted
  # access to parameters under this path.
  parameter_path = "/${var.project}/${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "terraform-takehome-challenge"
    },
    var.extra_tags,
  )
}
