current_stage = "preprod"

# Sub-prod stages share one account; prod has its own. The provider enforces
# this, so an apply with the wrong credentials fails before creating anything.
aws_account_id = "319580086754"

# Note the order: the preprod bucket is "etl-preprod", unlike the other stages
# (same name in boomi-resources and credit-backend).
snowflake_bucket_name = "ls-snowflake-etl-preprod"

# Created by operations; the plan fails if it does not exist.
netsuite_secret_name = "preprod/netsuite/suiteql/secret"

# FCM310 schedules stay off until the Boomi CUSTOMERS driver is switched off.
customer_schedule_enabled = false
customer_alert_email      = ""
