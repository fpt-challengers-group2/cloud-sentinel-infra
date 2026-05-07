# --- DynamoDB: Lưu lịch sử sự cố ---
resource "aws_dynamodb_table" "incident_history" {
  name         = "cloud-sentinel-securityincidenthistory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "finding_type"
  range_key    = "target_id"

  attribute {
    name = "finding_type"
    type = "S"
  }

  attribute {
    name = "target_id"
    type = "S"
  }

  tags = {
    Project = var.project_name
  }
}

# --- S3: Lưu trữ báo cáo bảo mật ---
resource "aws_s3_bucket" "reports" {
  bucket = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "reports_block" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}