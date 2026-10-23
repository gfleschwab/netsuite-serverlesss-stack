# --- Glue Assets S3 Bucket & Objects ---

resource "aws_s3_bucket" "glue_assets" {
  bucket = "${local.fn_prefix}-glue-scripts"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "glue_assets" {
  bucket                  = aws_s3_bucket.glue_assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "glue_script_historical_load" {
  bucket = aws_s3_bucket.glue_assets.id
  key    = "glue-scripts/netsuite2-historical-load.py"
  source = "${path.module}/../../assets/glue-scripts/netsuite2-historical-load.py"
  etag   = filemd5("${path.module}/../../assets/glue-scripts/netsuite2-historical-load.py")
  tags   = local.tags
}

resource "aws_s3_object" "glue_script_customer_extract" {
  bucket = aws_s3_bucket.glue_assets.id
  key    = "glue-scripts/fcm311-07-netsuite-customer-extract.py"
  source = "${path.module}/../../assets/glue-scripts/fcm311-07-netsuite-customer-extract.py"
  etag   = filemd5("${path.module}/../../assets/glue-scripts/fcm311-07-netsuite-customer-extract.py")
  tags   = local.tags
}

# Owned by operations; the stack only reads it.
data "aws_secretsmanager_secret" "netsuite" {
  name = var.netsuite_secret_name
}

data "aws_s3_bucket" "snowflake" {
  bucket = var.snowflake_bucket_name
}
