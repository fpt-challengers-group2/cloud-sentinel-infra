# Cấu hình cấp Account để API Gateway được phép ghi log
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gw_cloudwatch_role.arn
}

resource "aws_api_gateway_rest_api" "telegram_api" {
  name        = "${var.project_name}-telegram-webhook"
  description = "API Gateway for Telegram Webhook"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.telegram_api.id
  parent_id   = aws_api_gateway_rest_api.telegram_api.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "webhook_post" {
  rest_api_id   = aws_api_gateway_rest_api.telegram_api.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "webhook_integration" {
  rest_api_id             = aws_api_gateway_rest_api.telegram_api.id
  resource_id             = aws_api_gateway_resource.webhook.id
  http_method             = aws_api_gateway_method.webhook_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.sentinel_lambdas["lambda_approval_handler"].invoke_arn
}

resource "aws_api_gateway_deployment" "telegram_deployment" {
  depends_on = [aws_api_gateway_integration.webhook_integration]
  rest_api_id = aws_api_gateway_rest_api.telegram_api.id

  lifecycle {
    create_before_destroy = true
  }
}

# --- THÊM CLOUDWATCH LOG CHO API GATEWAY ---
resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/api-gateway/${var.project_name}-telegram-webhook"
  retention_in_days = 30
}

resource "aws_api_gateway_stage" "prod" {
  depends_on    = [aws_api_gateway_account.main] # Đợi cấp quyền xong mới tạo stage
  deployment_id = aws_api_gateway_deployment.telegram_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.telegram_api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format          = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      error          = "$context.error.messageString"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}

output "webhook_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/webhook"
}