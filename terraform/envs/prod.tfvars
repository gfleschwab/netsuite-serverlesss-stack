current_stage = "prod"

# Prod is its own account, with its own state bucket and deployment role.
aws_account_id = "470439681586"

snowflake_bucket_name = "ls-snowflake-prod-etl"

# Created by operations; the plan fails if it does not exist.
netsuite_secret_name = "prod/netsuite/suiteql/secret"

# FCM310 schedules stay off until the Boomi CUSTOMERS driver is switched off.
customer_schedule_enabled = false
customer_alert_email      = ""
