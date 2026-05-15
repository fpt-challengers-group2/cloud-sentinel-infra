# DynamoDB: Lưu lịch sử sự cố
resource "aws_dynamodb_table" "incident_history" {
  name         = "${var.project_name}-security-incident-history"
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

  attribute {
    name = "timestamp"
    type = "S"
  }

  global_secondary_index {
    name            = "TimestampIndex"
    hash_key        = "finding_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Project = var.project_name
  }
}

# DynamoDB: Lưu Task Tokens cho Step Functions
resource "aws_dynamodb_table" "task_tokens" {
  name         = "${var.project_name}-task-tokens"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "finding_id"

  attribute {
    name = "finding_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Project = var.project_name
  }
}

# S3: Lưu trữ báo cáo bảo mật
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

resource "aws_s3_bucket_versioning" "reports_versioning" {
  bucket = aws_s3_bucket.reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_caller_identity" "current" {}