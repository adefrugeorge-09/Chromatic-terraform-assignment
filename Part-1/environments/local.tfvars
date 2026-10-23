# Local development against MiniStack (docker compose up).
environment        = "local"
local_endpoint_url = "http://localhost:4566"

az_count           = 2
single_nat_gateway = true

# Emulator-friendly settings: no customer-managed KMS, no X-Ray, keep logs short.
create_kms_key     = false
api_key_required   = false
tracing_enabled    = false
log_retention_days = 1

api_throttling_burst_limit = 1000
api_throttling_rate_limit  = 1000
