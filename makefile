# NetSuite ETL — Terraform entry points
#
# Used by .github/workflows/deploy.yml and for running the same commands by hand.
# Follows the layout in salesforce-serverless-stack and rc015-aws-stack so the
# repos are driven the same way.
#
#   make plan STAGE=qa
#   make apply STAGE=qa
#   make apply STAGE=prod TFSTATE_BUCKET=platform-infra-terraform-state-prod

.PHONY: help test fmt validate init plan apply destroy

# ── Configuration ────────────────────────────────────────────────────────────
TF_DIR      := terraform
BACKEND_DIR := $(TF_DIR)/infrastructure
REGION      ?= us-west-2
STAGE       ?= dev
FORCE       ?= false

# Sub-prod stages share one state bucket and are separated by the key. prod has
# its own, in its own account, and must be passed explicitly.
TFSTATE_BUCKET ?= platform-infra-terraform-state-dev

# Constant across stages; it is the first segment of the state key.
STACK_NAME ?= netsuite-etl

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

# ── Checks ───────────────────────────────────────────────────────────────────

test: ## Run the Glue script unit tests
	@PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s tests -v

fmt: ## Check Terraform formatting
	@terraform fmt -check -recursive $(TF_DIR)

validate: ## Validate the Terraform configuration
	@terraform -chdir=$(BACKEND_DIR) init -backend=false -input=false >/dev/null
	@terraform -chdir=$(BACKEND_DIR) validate

# ── Terraform ────────────────────────────────────────────────────────────────

init: ## Init the Terraform backend for STAGE
	@if [ ! -f "$(TF_DIR)/envs/$(STAGE).tfvars" ]; then \
		echo "ERROR: $(TF_DIR)/envs/$(STAGE).tfvars does not exist."; \
		exit 1; \
	fi
	@if [ "$(STAGE)" = "prod" ] && [ "$(TFSTATE_BUCKET)" = "platform-infra-terraform-state-dev" ]; then \
		echo "ERROR: deploying to prod with the sub-prod state bucket."; \
		echo "       Pass TFSTATE_BUCKET=platform-infra-terraform-state-prod explicitly."; \
		exit 1; \
	fi
	@echo "-> init $(STAGE) (bucket: $(TFSTATE_BUCKET))"
	@terraform -chdir=$(BACKEND_DIR) init -input=false -reconfigure \
		-backend-config="bucket=$(TFSTATE_BUCKET)" \
		-backend-config="key=$(STACK_NAME)/$(STAGE)/terraform.tfstate" \
		-backend-config="region=$(REGION)" \
		-backend-config="use_lockfile=true"

plan: init ## Plan STAGE into a plan file
	@echo "-> plan $(STAGE)"
	@terraform -chdir=$(BACKEND_DIR) plan -input=false -lock-timeout=5m \
		-var-file=../envs/$(STAGE).tfvars \
		-out=tfplan

# Applies the saved plan rather than re-planning, so what is deployed cannot
# drift from what was shown and approved.
apply: plan ## Plan and apply STAGE
	@echo "-> apply $(STAGE)"
	@terraform -chdir=$(BACKEND_DIR) apply -input=false -lock-timeout=5m tfplan

destroy: init ## Destroy STAGE (prod requires FORCE=true)
ifeq ($(STAGE),prod)
	@if [ "$(FORCE)" != "true" ]; then \
		echo "ERROR: refusing to destroy prod without FORCE=true."; \
		exit 1; \
	fi
endif
	@terraform -chdir=$(BACKEND_DIR) destroy -input=false -lock-timeout=5m \
		-var-file=../envs/$(STAGE).tfvars
