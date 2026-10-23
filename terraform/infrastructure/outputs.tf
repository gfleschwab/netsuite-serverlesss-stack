output "glue_assets_bucket" {
  description = "The S3 bucket containing the Glue scripts"
  value       = aws_s3_bucket.glue_assets.bucket
}

output "historical_load_state_machine_arn" {
  description = "Start with {\"startDate\": \"...\", \"endDate\": \"...\"} to run a historical load"
  value       = aws_sfn_state_machine.historical_load.arn
}

output "customer_state_machine_arn" {
  description = "FCM310 Customer state machine; optional input {\"fromDate\": \"...\"} replays from that date"
  value       = aws_sfn_state_machine.customer.arn
}

output "customer_glue_job_name" {
  description = "FCM311.07 Customer extract Glue job"
  value       = aws_glue_job.customer_extract.name
}

output "customer_watermark_parameter" {
  description = "SSM parameter holding the Customer Last Successful Run Date (UTC)"
  value       = local.customer_watermark_parameter
}

output "customer_alerts_topic_arn" {
  description = "SNS topic receiving FCM310 Customer failure alerts"
  value       = aws_sns_topic.customer_alerts.arn
}
