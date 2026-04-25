locals {
  # Bổ sung lambda_invoker vào danh sách
  lambda_list = ["lambda_parser", "lambda_history", "lambda_knowledge", "lambda_saver", "lambda_invoker"]
}

data "archive_file" "lambda_zip" {
  for_each    = toset(local.lambda_list)
  type        = "zip"
  source_dir  = "${path.module}/../src/${each.key}"
  output_path = "${path.module}/${each.key}.zip"
}

resource "aws_lambda_function" "sentinel_lambdas" {
  for_each      = toset(local.lambda_list)
  function_name = "${var.project_name}-${each.key}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  
  # Cấp thời gian chạy tối đa 3 phút cho invoker chờ Agent phản hồi
  timeout       = each.key == "lambda_invoker" ? 180 : (each.key == "lambda_knowledge" ? 60 : 30)
  memory_size   = each.key == "lambda_knowledge" ? 256 : 128

  filename         = data.archive_file.lambda_zip[each.key].output_path
  source_code_hash = data.archive_file.lambda_zip[each.key].output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.incident_history.name
      REPORT_BUCKET_NAME  = aws_s3_bucket.reports.id
      PINECONE_API_KEY    = var.pinecone_api_key
      PINECONE_HOST       = var.pinecone_host
    }
  }
}

resource "aws_lambda_permission" "allow_bedrock" {
  for_each      = toset(["lambda_parser", "lambda_history", "lambda_knowledge"])
  statement_id  = "AllowBedrockInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sentinel_lambdas[each.key].function_name
  principal     = "bedrock.amazonaws.com"
}