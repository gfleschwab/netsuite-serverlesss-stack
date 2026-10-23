# =============================================================================
# FCM310 / FCM311.07 — NetSuite Customer extract (CHG0032633)
# =============================================================================
#
#   EventBridge Scheduler (FCM310 crons) -> Step Functions (FCM310 Customer)
#     -> Glue Python shell (FCM311.07) -> S3 Snowpipe folder -> Snowpipe -> Snowflake
#
# Only the CUSTOMERS driver moves to AWS; every other FCM310 driver keeps
# running in Boomi. The Last Successful Run Date lives in an SSM parameter that
# the job creates and only advances after the file is in S3, so it is not a
# Terraform resource (an apply must never move it).
# =============================================================================

locals {
  customer_job_name            = "${local.fn_prefix}-fcm311-07-customer-extract"
  customer_watermark_parameter = "/${var.stack_name}/${var.current_stage}/fcm311-07/customer/last-successful-run-date"
  customer_output_prefix       = "${trimsuffix(var.customer_output_prefix, "/")}/"

  # Same three schedules as the Boomi FCM310 parent.
  customer_schedules = {
    "0430"    = { expression = "cron(30 4 * * ? *)", description = "FCM310 Customer - every day 04:30" }
    "0805"    = { expression = "cron(5 8 * * ? *)", description = "FCM310 Customer - every day 08:05" }
    "daytime" = { expression = "cron(30 10-16/3 ? * MON-SAT *)", description = "FCM310 Customer - Monday to Saturday every 3 hours from 10:30 to 16:30" }
  }
}

# --- Glue Job (FCM311.07) ---

resource "aws_iam_role" "customer_glue_job" {
  name = "${local.fn_prefix}-customer-glue-job-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "customer_glue_service" {
  role       = aws_iam_role.customer_glue_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "customer_glue_job" {
  name = "CustomerGlueJobAccessPolicy"
  role = aws_iam_role.customer_glue_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.glue_assets.arn}/${aws_s3_object.glue_script_customer_extract.key}"
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${data.aws_s3_bucket.snowflake.arn}/${local.customer_output_prefix}*"
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = data.aws_secretsmanager_secret.netsuite.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:PutParameter"]
        Resource = "arn:aws:ssm:${var.region}:${local.account_id}:parameter${local.customer_watermark_parameter}"
      },
      {
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "NetSuiteETL" } }
      }
    ]
  })
}

# Python shell is enough: one SuiteQL extract streamed to a single file, no Spark.
resource "aws_glue_job" "customer_extract" {
  name         = local.customer_job_name
  description  = "FCM311.07 - NetSuite Customer delta extract to the Snowpipe S3 folder (replaces FCM311.07-NS.CUST.BOOMI-CHILD.TRG)."
  role_arn     = aws_iam_role.customer_glue_job.arn
  glue_version = "3.0"
  max_capacity = 1
  timeout      = var.customer_job_timeout_minutes
  max_retries  = 0

  # A schedule that fires while the previous run is still going is skipped by
  # the state machine; that run picks the changes up.
  execution_property {
    max_concurrent_runs = 1
  }

  command {
    name            = "pythonshell"
    script_location = "s3://${aws_s3_bucket.glue_assets.bucket}/${aws_s3_object.glue_script_customer_extract.key}"
    python_version  = "3.9"
  }

  default_arguments = {
    "--job-language"              = "python"
    "--additional-python-modules" = "requests==2.31.0,oauthlib==3.2.2,requests-oauthlib==1.3.1,tzdata==2024.1"
    "--secret_name"               = var.netsuite_secret_name
    "--output_bucket"             = var.snowflake_bucket_name
    "--output_prefix"             = local.customer_output_prefix
    "--watermark_parameter"       = local.customer_watermark_parameter
    "--netsuite_timezone"         = var.customer_netsuite_timezone
    "--overlap_minutes"           = tostring(var.customer_overlap_minutes)
    "--from_date"                 = "auto"
  }

  tags = merge(local.tags, { Integration = "FCM311.07" })
}

# --- Step Functions (FCM310 Customer driver) ---

resource "aws_iam_role" "customer_state_machine" {
  name = "${local.fn_prefix}-customer-sfn-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "customer_state_machine" {
  name = "RunCustomerGlueJob"
  role = aws_iam_role.customer_state_machine.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
      Resource = aws_glue_job.customer_extract.arn
    }]
  })
}

# Optional input {"fromDate": "2026-10-23T11:30:00Z"} replays from that date.
resource "aws_sfn_state_machine" "customer" {
  name     = "${local.fn_prefix}-fcm310-customer"
  role_arn = aws_iam_role.customer_state_machine.arn
  tags     = merge(local.tags, { Integration = "FCM310" })

  definition = jsonencode({
    Comment        = "FCM310 (AWS) - runs FCM311.07 NetSuite Customer extract. Optional input fromDate overrides the Last Successful Run Date."
    StartAt        = "HasFromDateOverride"
    TimeoutSeconds = 10800
    States = {
      HasFromDateOverride = {
        Type    = "Choice"
        Choices = [{ Variable = "$.fromDate", IsPresent = true, Next = "UseFromDateOverride" }]
        Default = "UseLastSuccessfulRunDate"
      }
      UseFromDateOverride = {
        Type       = "Pass"
        Parameters = { "fromDate.$" = "$.fromDate" }
        Next       = "RunFCM311_07CustomerExtract"
      }
      UseLastSuccessfulRunDate = {
        Type       = "Pass"
        Parameters = { fromDate = "auto" }
        Next       = "RunFCM311_07CustomerExtract"
      }
      RunFCM311_07CustomerExtract = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName   = aws_glue_job.customer_extract.name
          Arguments = { "--from_date.$" = "$.fromDate" }
        }
        Retry = [
          { ErrorEquals = ["Glue.ConcurrentRunsExceededException"], MaxAttempts = 0 },
          { ErrorEquals = ["States.TaskFailed"], IntervalSeconds = 300, MaxAttempts = 1 }
        ]
        Catch = [
          { ErrorEquals = ["Glue.ConcurrentRunsExceededException"], Next = "SkippedPreviousRunStillActive" }
        ]
        End = true
      }
      SkippedPreviousRunStillActive = {
        Type    = "Succeed"
        Comment = "Previous extract still running; it picks these changes up because the LSRD only moves on success."
      }
    }
  })
}

# --- Schedules (FCM310 crons) ---

resource "aws_iam_role" "customer_scheduler" {
  name = "${local.fn_prefix}-customer-scheduler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "customer_scheduler" {
  name = "StartCustomerStateMachine"
  role = aws_iam_role.customer_scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.customer.arn
    }]
  })
}

resource "aws_scheduler_schedule" "customer" {
  for_each = local.customer_schedules

  name                         = "${local.fn_prefix}-fcm310-customer-${each.key}"
  description                  = each.value.description
  schedule_expression          = each.value.expression
  schedule_expression_timezone = var.customer_schedule_timezone
  state                        = var.customer_schedule_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.customer.arn
    role_arn = aws_iam_role.customer_scheduler.arn
    input    = jsonencode({})
  }
}

# --- Failure alerts ---

resource "aws_sns_topic" "customer_alerts" {
  name         = "${local.fn_prefix}-fcm310-customer-alerts"
  display_name = "FCM310 NetSuite Customer alerts"
  tags         = local.tags
}

resource "aws_sns_topic_subscription" "customer_alerts_email" {
  count     = var.customer_alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.customer_alerts.arn
  protocol  = "email"
  endpoint  = var.customer_alert_email
}

resource "aws_cloudwatch_event_rule" "customer_failed" {
  name        = "${local.fn_prefix}-fcm310-customer-failed"
  description = "Alerts when the FCM310 Customer execution (FCM311.07 Glue job) fails, times out or is aborted."
  event_pattern = jsonencode({
    source        = ["aws.states"]
    "detail-type" = ["Step Functions Execution Status Change"]
    detail = {
      status          = ["FAILED", "TIMED_OUT", "ABORTED"]
      stateMachineArn = [aws_sfn_state_machine.customer.arn]
    }
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "customer_failed_sns" {
  rule      = aws_cloudwatch_event_rule.customer_failed.name
  target_id = "CustomerAlertsTopic"
  arn       = aws_sns_topic.customer_alerts.arn

  input_transformer {
    input_paths = {
      status    = "$.detail.status"
      execution = "$.detail.executionArn"
      time      = "$.time"
    }
    input_template = "\"[${var.current_stage}] FCM310/FCM311.07 NetSuite Customer extract <status> at <time>. Execution: <execution>. The Last Successful Run Date was NOT advanced; follow docs/runbooks/FCM310-FCM311.07-customer.md.\""
  }
}

resource "aws_sns_topic_policy" "customer_alerts" {
  arn = aws_sns_topic.customer_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.customer_alerts.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.customer_failed.arn } }
    }]
  })
}
