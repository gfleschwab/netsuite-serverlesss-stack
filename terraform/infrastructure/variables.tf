variable "region" {
  type    = string
  default = "us-west-2"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account this stage deploys into. Sub-prod stages share one account; prod has its own. Enforced by the provider, so a wrong-account apply fails before creating anything."
}

variable "current_stage" {
  type        = string
  description = "The deployment stage (dev, qa, preprod, prod)"

  validation {
    condition     = contains(["dev", "qa", "preprod", "prod"], var.current_stage)
    error_message = "current_stage must be one of dev, qa, preprod, prod."
  }
}

variable "stack_name" {
  type        = string
  description = "The name of the stack"
  default     = "netsuite-etl"
}

variable "stack_tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default = {
    "Portfolio Owner"     = "Integrations"
    "Support Group"       = "Baufest"
    "Project"             = "NetSuite ETL Integration"
    "Data Classification" = "Confidential"
    "Exposure"            = "Internal"
    "Source"              = "Terraform"
  }
}

variable "snowflake_bucket_name" {
  type        = string
  description = "The stage's Snowflake ETL bucket, read by Snowpipe (e.g. ls-snowflake-dev-etl)."
}

variable "netsuite_secret_name" {
  type        = string
  description = "Secrets Manager secret with the NetSuite SuiteQL TBA credentials (BASE_URL, ACCOUNT_ID, CONSUMER_KEY, CONSUMER_SECRET, TOKEN_ID, TOKEN_SECRET). Created by operations, never by this stack."
}

# --- Historical load (Transaction / TransactionLine) ---

variable "historical_output_prefix" {
  type        = string
  description = "Prefix in the Snowflake bucket where the historical load writes Parquet, one load_date= folder per run."
  default     = "SNOWPIPE/NETSUITE/HISTORICALLOAD/TRANSACTIONLINE"
}

# --- FCM310 / FCM311.07 Customer extract (CHG0032633) ---

variable "customer_output_prefix" {
  type        = string
  description = "Prefix in the Snowflake bucket read by the Customer Snowpipe (Boomi ML_Snowpipe_Folder of FCM311.07)."
  default     = "SNOWPIPE/NETSUITE/CUSTOMERS/"
}

variable "customer_netsuite_timezone" {
  type        = string
  description = "Timezone preference of the NetSuite user that owns the token. SuiteQL reads and returns dates in it."
  default     = "America/Los_Angeles"
}

variable "customer_overlap_minutes" {
  type        = number
  description = "Minutes subtracted from the Last Successful Run Date on every extract."
  default     = 0
}

variable "customer_job_timeout_minutes" {
  type    = number
  default = 60
}

variable "customer_schedule_enabled" {
  type        = bool
  description = "Turns the FCM310 Customer schedules on. Keep false until the Boomi CUSTOMERS driver is switched off (cutover)."
  default     = false
}

variable "customer_schedule_timezone" {
  type        = string
  description = "Timezone of the FCM310 schedules. Boomi runs them at UTC-7."
  default     = "Etc/GMT+7"
}

variable "customer_alert_email" {
  type        = string
  description = "Optional email subscribed to the Customer failure alerts. Empty for none."
  default     = ""
}
