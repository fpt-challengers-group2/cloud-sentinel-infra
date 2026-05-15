# IAM Role cho Lambda Functions
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect = "Allow"
        Resource = [
          aws_dynamodb_table.incident_history.arn,
          aws_dynamodb_table.task_tokens.arn,
          "${aws_dynamodb_table.incident_history.arn}/*"
        ]
      },
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.reports.arn}/*"
      },
      {
        Action = [
          "bedrock:InvokeAgent",
          "bedrock:InvokeModel"
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "states:SendTaskSuccess",
          "states:SendTaskFailure"
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "cognito-idp:ListUsers",
          "cognito-idp:AdminGetUser"
        ]
        Effect = "Allow"
        Resource = aws_cognito_user_pool.admin_pool.arn
      }
    ]
  })
}

# IAM Role cho Step Functions
resource "aws_iam_role" "sf_role" {
  name = "${var.project_name}-sf-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sf_policy" {
  name = "${var.project_name}-sf-policy"
  role = aws_iam_role.sf_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaForStepFunctions"
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.sentinel_lambdas["lambda_parser"].arn,
          aws_lambda_function.sentinel_lambdas["lambda_history"].arn,
          aws_lambda_function.sentinel_lambdas["lambda_knowledge"].arn,
          aws_lambda_function.sentinel_lambdas["lambda_advisor"].arn,
          aws_lambda_function.sentinel_lambdas["lambda_telegram_sender"].arn,
          aws_lambda_function.sentinel_lambdas["lambda_executor"].arn
        ]
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Role cho Bedrock Agents
resource "aws_iam_role" "agent_role" {
  name = "${var.project_name}-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "agent_policy" {
  name = "${var.project_name}-agent-policy"
  role = aws_iam_role.agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = "lambda:InvokeFunction"
        Effect   = "Allow"
        Resource = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-*"
      }
    ]
  })
}

# ==========================================
# IAM Role cho API Gateway ghi log vào CloudWatch
# ==========================================
resource "aws_iam_role" "api_gw_cloudwatch_role" {
  name = "${var.project_name}-api-gw-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gw_cw_policy" {
  role       = aws_iam_role.api_gw_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}