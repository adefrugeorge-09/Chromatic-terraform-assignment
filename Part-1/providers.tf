provider "aws" {
  region = var.aws_region

  # Every resource gets the same baseline tags. Modules only add resource
  # specific tags (e.g. Name) on top of these.
  default_tags {
    tags = local.common_tags
  }

  # ---------------------------------------------------------------------------
  # Local development (MiniStack). All of the attributes below evaluate to
  # null / false for real AWS environments, which the provider treats as
  # "not set", so a single provider block serves every environment.
  # ---------------------------------------------------------------------------
  access_key                  = local.is_local ? "test" : null
  secret_key                  = local.is_local ? "test" : null
  skip_credentials_validation = local.is_local
  skip_metadata_api_check     = local.is_local
  s3_use_path_style           = local.is_local

  endpoints {
    apigateway   = var.local_endpoint_url
    apigatewayv2 = var.local_endpoint_url
    cloudwatch   = var.local_endpoint_url
    dynamodb     = var.local_endpoint_url
    ec2          = var.local_endpoint_url
    iam          = var.local_endpoint_url
    kms          = var.local_endpoint_url
    lambda       = var.local_endpoint_url
    logs         = var.local_endpoint_url
    s3           = var.local_endpoint_url
    ssm          = var.local_endpoint_url
    sts          = var.local_endpoint_url
  }
}
