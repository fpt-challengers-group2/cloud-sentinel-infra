locals {
  lambda_list = [
    "lambda_parser",
    "lambda_history", 
    "lambda_knowledge",
    "lambda_advisor",
    "lambda_telegram_sender",
    "lambda_approval_handler",
    "lambda_executor",
    "lambda_token_cleaner"
  ]
}

# ==========================================
# CÀI ĐẶT THƯ VIỆN TỰ ĐỘNG BẰNG TERRAFORM
# ==========================================
resource "null_resource" "install_dependencies" {
  triggers = {
    # Tính năng thông minh: Chỉ chạy lại pip install nếu bạn sửa file requirements.txt
    requirements = filemd5("${path.module}/../src/requirements.txt")
  }

  provisioner "local-exec" {
    # Lệnh cài đặt thư viện thẳng vào các thư mục Lambda cần thiết
    command = "pip install pinecone -t ${path.module}/../src/lambda_knowledge/ --platform manylinux2014_x86_64 --only-binary=:all: && pip install requests -t ${path.module}/../src/lambda_telegram_sender/ && pip install requests -t ${path.module}/../src/lambda_approval_handler/"
  }
}

data "archive_file" "lambda_zip" {
  for_each    = toset(local.lambda_list)
  type        = "zip"
  source_dir  = "${path.module}/../src/${each.key}"
  output_path = "${path.module}/lambda_zips/${each.key}.zip"

  # BẮT BUỘC: Ép Terraform phải đợi chạy xong null_resource (cài thư viện) rồi mới được nén file zip
  depends_on = [null_resource.install_dependencies]
}

# --- THÊM CLOUDWATCH LOG GROUP CHO CÁC LAMBDAS ---
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each          = toset(local.lambda_list)
  name              = "/aws/lambda/${var.project_name}-${each.key}"
  retention_in_days = 30 # Xóa log sau 30 ngày để tiết kiệm phí

  tags = {
    Project = var.project_name
  }
}

resource "aws_lambda_function" "sentinel_lambdas" {
  for_each      = toset(local.lambda_list)
  function_name = "${var.project_name}-${each.key}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  timeout = each.key == "lambda_advisor" ? 180 : (
    each.key == "lambda_knowledge" ? 60 : 30
  )
  memory_size = each.key == "lambda_knowledge" ? 256 : 128

  filename         = data.archive_file.lambda_zip[each.key].output_path
  source_code_hash = data.archive_file.lambda_zip[each.key].output_base64sha256

  environment {
    variables = {
      DYNAMODB_HISTORY_TABLE    = aws_dynamodb_table.incident_history.name
      DYNAMODB_TOKEN_TABLE      = aws_dynamodb_table.task_tokens.name
      REPORT_BUCKET_NAME        = aws_s3_bucket.reports.id
      PINECONE_API_KEY          = var.pinecone_api_key
      PINECONE_HOST             = var.pinecone_host
      TELEGRAM_TOKEN            = var.telegram_token
      TELEGRAM_CHAT_ID          = var.telegram_chat_id
      COGNITO_USER_POOL_ID      = aws_cognito_user_pool.admin_pool.id
      ADVISOR_AGENT_ID          = aws_bedrockagent_agent.advisor.id
      # Sử dụng TSTALIASID để gọi thẳng vào bản Draft của Agent, phá vỡ vòng lặp Cycle
      ADVISOR_AGENT_ALIAS_ID    = "TSTALIASID"
      SUPERVISOR_AGENT_ID       = aws_bedrockagent_agent.supervisor.id
      SUPERVISOR_AGENT_ALIAS_ID = "TSTALIASID"
      REGION                    = var.region
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = {
    Project = var.project_name
  }
}

resource "aws_lambda_permission" "allow_bedrock" {
  for_each      = toset(["lambda_parser", "lambda_history", "lambda_knowledge"])
  statement_id  = "AllowBedrockInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sentinel_lambdas[each.key].function_name
  principal     = "bedrock.amazonaws.com"
}

resource "aws_lambda_permission" "allow_stepfunctions" {
  for_each      = toset(["lambda_parser", "lambda_history", "lambda_knowledge", "lambda_advisor", "lambda_telegram_sender", "lambda_executor"])
  statement_id  = "AllowStepFunctionsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sentinel_lambdas[each.key].function_name
  principal     = "states.amazonaws.com"
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sentinel_lambdas["lambda_approval_handler"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.telegram_api.execution_arn}/*/*"
}