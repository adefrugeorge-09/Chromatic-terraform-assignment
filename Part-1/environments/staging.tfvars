# Staging: production-like topology at reduced cost.
environment = "staging"
aws_region  = "us-east-1"
vpc_cidr    = "10.1.0.0/16"

az_count           = 2
single_nat_gateway = true # one NAT is enough; staging can tolerate an AZ outage

lambda_memory_size = 256
lambda_timeout     = 10
log_retention_days = 14

api_throttling_burst_limit = 100
api_throttling_rate_limit  = 50
api_cors_allowed_origins   = ["https://staging.example.com"]

create_kms_key = true
# kms_key_administrators = ["arn:aws:iam::123456789012:role/platform-admin"]

extra_tags = {
  Team       = "platform"
  CostCenter = "eng-platform"
}
