terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
  required_version = ">= 1.10.0"

  backend "s3" {
    # Sub-prod stages share one bucket and are separated by the key; prod has
    # its own, in its own account. Driven by `make init` / `make apply`, which
    # pass:
    # terraform init -backend-config="bucket=<state-bucket>" \
    #                -backend-config="key=netsuite-etl/{stage}/terraform.tfstate" \
    #                -backend-config="region=us-west-2" \
    #                -backend-config="use_lockfile=true"
  }
}

provider "aws" {
  region = var.region

  # Sub-prod and prod live in different accounts. This makes a run with the
  # wrong credentials fail during plan rather than creating a duplicate stack
  # in the wrong place.
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = merge(var.stack_tags, {
      Environment = var.current_stage
    })
  }
}

data "aws_caller_identity" "current" {}

locals {
  fn_prefix  = "${var.stack_name}-${var.current_stage}"
  account_id = data.aws_caller_identity.current.account_id
  tags       = merge(var.stack_tags, { Environment = var.current_stage })
}
