# Production.
environment = "production"
aws_region  = "us-east-1"
vpc_cidr    = "10.2.0.0/16"

az_count           = 3
single_nat_gateway = false # one NAT gateway per AZ: no single point of failure

lambda_memory_size          = 512
lambda_timeout              = 10
lambda_reserved_concurrency = 200 # protect downstreams and the account pool
log_retention_days          = 90

api_throttling_burst_limit = 500
api_throttling_rate_limit  = 250
api_cors_allowed_origins   = ["https://app.example.com"]

create_kms_key = true
# kms_key_administrators = ["arn:aws:iam::123456789012:role/platform-admin"]

extra_tags = {
  Team       = "platform"
  CostCenter = "eng-platform"
  DataClass  = "internal"
}
