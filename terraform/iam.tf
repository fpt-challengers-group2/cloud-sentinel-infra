# --- 1. IAM Role cho Lambda Functions ---
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
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = "dynamodb:GetItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.incident_history.arn
      },
      {
        Action = "s3:PutObject"
        Effect = "Allow"
        Resource = "${aws_s3_bucket.reports.arn}/*"
      },
      {
        # Cấp quyền cho Lambda Invoker gọi Bedrock Agent
        Action = "bedrock:InvokeAgent"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

# --- 2. IAM Role cho Step Functions ---
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
          aws_lambda_function.sentinel_lambdas["lambda_invoker"].arn,
          aws_lambda_function.sentinel_lambdas["lambda_saver"].arn
        ]
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutLogEvents",
          "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- 3. IAM Role cho Bedrock Agents ---
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
        # Cấp quyền cho Agent gọi Foundation Model (Claude)
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
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