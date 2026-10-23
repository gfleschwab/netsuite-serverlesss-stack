# =============================================================================
# Historical load — NetSuite TransactionLine (SuiteQL -> Parquet)
# =============================================================================
#
# Started by hand with {"startDate": "...", "endDate": "..."}. The state machine
# splits the range into chunks (dateGenerator Lambda) and runs the Glue job once
# per chunk, one at a time, through triggerNetsuiteEtl, which waits for the run
# and reports back with the task token.
# =============================================================================

# --- Glue Job ---

resource "aws_iam_role" "historical_glue_job" {
  name = "${local.fn_prefix}-historical-glue-job-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "historical_glue_service" {
  role       = aws_iam_role.historical_glue_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "historical_glue_job" {
  name = "GlueJobAccessPolicy"
  role = aws_iam_role.historical_glue_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.glue_assets.arn}/${aws_s3_object.glue_script_historical_load.key}"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.glue_assets.arn}/temporary/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${data.aws_s3_bucket.snowflake.arn}/${var.historical_output_prefix}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = [aws_s3_bucket.glue_assets.arn, data.aws_s3_bucket.snowflake.arn]
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = data.aws_secretsmanager_secret.netsuite.arn
      }
    ]
  })
}

resource "aws_glue_job" "historical_load" {
  name              = "${local.fn_prefix}-netsuite2-historical-load"
  description       = "NetSuite TransactionLine historical load (SuiteQL REST to Parquet), one date range per run."
  role_arn          = aws_iam_role.historical_glue_job.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 10
  execution_class   = "FLEX"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_assets.bucket}/${aws_s3_object.glue_script_historical_load.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--TempDir"                   = "s3://${aws_s3_bucket.glue_assets.bucket}/temporary/"
    "--job-language"              = "python"
    "--additional-python-modules" = "requests_oauthlib==1.3.1,pandas==1.5.3"
    "--enable-metrics"            = "true"
    "--secret_name"               = var.netsuite_secret_name
    "--output_path"               = "s3://${var.snowflake_bucket_name}/${var.historical_output_prefix}"
  }

  tags = local.tags
}

# --- Lambda Functions ---

data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-package.zip"

  source {
    content  = file("${path.module}/../../handler.js")
    filename = "handler.js"
  }
  source {
    content  = file("${path.module}/../../dateGeneratorHandler.js")
    filename = "dateGeneratorHandler.js"
  }
  # Carries "type": "module" so the handlers load as ES modules.
  source {
    content  = file("${path.module}/../../package.json")
    filename = "package.json"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${local.fn_prefix}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_glue_sfn" {
  name = "RunHistoricalGlueJobPolicy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["glue:StartJobRun", "glue:GetJobRun"]
        Resource = aws_glue_job.historical_load.arn
      },
      {
        # Task-token callbacks carry no resource of their own.
        Effect   = "Allow"
        Action   = ["states:SendTaskSuccess", "states:SendTaskFailure"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "date_generator" {
  function_name    = "${local.fn_prefix}-dateGenerator"
  description      = "Generates a list of daily date ranges for a historical load."
  role             = aws_iam_role.lambda_exec.arn
  runtime          = "nodejs20.x"
  handler          = "dateGeneratorHandler.handler"
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  tags             = local.tags
}

resource "aws_lambda_function" "trigger_netsuite_etl" {
  function_name    = "${local.fn_prefix}-triggerNetsuiteEtl"
  description      = "Triggers the NetSuite ETL Glue job to process a single day's data."
  role             = aws_iam_role.lambda_exec.arn
  runtime          = "nodejs20.x"
  handler          = "handler.handler"
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  # Polls the Glue run every 30s until it finishes.
  timeout = 900

  environment {
    variables = {
      GLUE_JOB_NAME = aws_glue_job.historical_load.name
      SECRET_NAME   = var.netsuite_secret_name
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "date_generator" {
  name              = "/aws/lambda/${aws_lambda_function.date_generator.function_name}"
  retention_in_days = var.current_stage == "prod" ? 0 : 30
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "trigger_netsuite_etl" {
  name              = "/aws/lambda/${aws_lambda_function.trigger_netsuite_etl.function_name}"
  retention_in_days = var.current_stage == "prod" ? 0 : 30
  tags              = local.tags
}

# --- Step Functions ---

resource "aws_iam_role" "historical_state_machine" {
  name = "${local.fn_prefix}-historical-sfn-role"
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

resource "aws_iam_role_policy" "historical_state_machine" {
  name = "InvokeHistoricalLambdas"
  role = aws_iam_role.historical_state_machine.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = [aws_lambda_function.date_generator.arn, aws_lambda_function.trigger_netsuite_etl.arn]
    }]
  })
}

resource "aws_sfn_state_machine" "historical_load" {
  name     = "${local.fn_prefix}-historical-load"
  role_arn = aws_iam_role.historical_state_machine.arn
  tags     = local.tags

  definition = jsonencode({
    Comment = "Runs the historical Glue job chunk by chunk, one at a time, to stay under NetSuite's rate limits."
    StartAt = "GenerateMonthlyChunks"
    States = {
      GenerateMonthlyChunks = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.date_generator.arn
          Payload = {
            "startDate.$" = "$.startDate"
            "endDate.$"   = "$.endDate"
          }
        }
        ResultPath = "$.monthlyChunks"
        Next       = "ProcessMonthlyChunks"
      }
      ProcessMonthlyChunks = {
        Type           = "Map"
        ItemsPath      = "$.monthlyChunks.Payload"
        MaxConcurrency = 1
        Iterator = {
          StartAt = "GenerateDailyDates"
          States = {
            GenerateDailyDates = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.date_generator.arn
                Payload = {
                  "startDate.$" = "$.startDate"
                  "endDate.$"   = "$.endDate"
                }
              }
              ResultPath = "$.dailyDates"
              Next       = "ProcessDailyJobs"
            }
            ProcessDailyJobs = {
              Type           = "Map"
              ItemsPath      = "$.dailyDates.Payload"
              MaxConcurrency = 1
              Iterator = {
                StartAt = "StartDailyGlueJob"
                States = {
                  StartDailyGlueJob = {
                    Type     = "Task"
                    Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
                    Parameters = {
                      FunctionName = aws_lambda_function.trigger_netsuite_etl.arn
                      Payload = {
                        "startDate.$" = "$.startDate"
                        "endDate.$"   = "$.endDate"
                        "TaskToken.$" = "$$.Task.Token"
                      }
                    }
                    Catch = [{
                      ErrorEquals = ["States.TaskFailed"]
                      Next        = "FailState"
                    }]
                    End = true
                  }
                  FailState = {
                    Type  = "Fail"
                    Cause = "Glue job failed"
                    Error = "JobRunFailed"
                  }
                }
              }
              End = true
            }
          }
        }
        End = true
      }
    }
  })
}
