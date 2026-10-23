current_stage = "dev"

# Sub-prod stages share one account; prod has its own. The provider enforces
# this, so an apply with the wrong credentials fails before creating anything.
aws_account_id = "319580086754"

snowflake_bucket_name = "ls-snowflake-dev-etl"

# Created by operations; the plan fails if it does not exist.
netsuite_secret_name = "dev/netsuite/suiteql/secret"

# FCM310 schedules stay off until the Boomi CUSTOMERS driver is switched off.
customer_schedule_enabled = false
customer_alert_email      = ""
