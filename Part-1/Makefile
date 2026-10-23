# Convenience wrapper so every engineer (and CI) runs Terraform the same way.
#
#   make init  ENV=staging
#   make plan  ENV=staging
#   make apply ENV=production
#
# ENV=local targets the MiniStack emulator and uses local state.

ENV ?= local
TFVARS := environments/$(ENV).tfvars
BACKEND := environments/$(ENV).s3.tfbackend
TF ?= terraform

ifeq ($(ENV),local)
  INIT_ARGS := -backend=false
else
  INIT_ARGS := -backend-config=$(BACKEND) -reconfigure
endif

.PHONY: help deps init fmt validate lint test plan apply destroy clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

deps: ## Install Lambda dependencies (production only)
	cd code && npm ci --omit=dev --no-audit --no-fund

init: ## terraform init for $(ENV)
	$(TF) init $(INIT_ARGS)

fmt: ## Format all Terraform files
	$(TF) fmt -recursive

validate: init ## terraform validate
	$(TF) validate

lint: ## tflint across root and modules
	tflint --init
	tflint --recursive --config "$(CURDIR)/.tflint.hcl"

test: ## Unit tests for the Lambda
	cd code && npm test

plan: deps init ## terraform plan for $(ENV)
	$(TF) plan -var-file=$(TFVARS) -out=tfplan.$(ENV)

apply: ## Apply the plan produced by `make plan ENV=$(ENV)`
	$(TF) apply tfplan.$(ENV)

destroy: init ## Destroy $(ENV)
	$(TF) destroy -var-file=$(TFVARS)

clean: ## Remove build artefacts and plans
	rm -rf build tfplan.* .terraform
