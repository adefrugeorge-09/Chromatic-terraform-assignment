# Remote state lives in S3, one state file per environment. The bucket and key
# are supplied at init time from environments/<env>.s3.tfbackend so that this
# file never has to change between environments:
#
#   terraform init -backend-config=environments/staging.s3.tfbackend
#
# State locking uses S3's native conditional writes (use_lockfile = true in
# the .tfbackend file), so no DynamoDB table is needed.
#
# For local development against MiniStack there is no S3 bucket to talk to, so
# the backend is disabled and state is kept in the working directory:
#
#   terraform init -backend=false      # or: make init ENV=local
terraform {
  backend "s3" {}
}
