resource "aws_cloudwatch_log_group" "sf_logs" {
  name              = "/aws/vendedlogs/states/${var.project_name}-orchestrator"
  retention_in_days = 30
}

resource "aws_sfn_state_machine" "orchestrator" {
  name     = "${var.project_name}-orchestrator"
  role_arn = aws_iam_role.sf_role.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sf_logs.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  definition = jsonencode({
    Comment = "CloudSentinel AI Security Orchestrator"
    StartAt = "Parse Finding"
    States = {
      "Parse Finding": {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.sentinel_lambdas["lambda_parser"].arn
          Payload = {
            "detail.$" = "$.detail"
          }
        }
        ResultPath = "$.parsed_finding"
        Next       = "Check Precedent"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
      },
      "Check Precedent": {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.sentinel_lambdas["lambda_history"].arn
          Payload = {
            "finding_type.$" = "$.parsed_finding.Payload.finding_type"
            "target_id.$"    = "$.parsed_finding.Payload.target_id"
            "finding_id.$"   = "$.parsed_finding.Payload.finding_id"
          }
        }
        ResultPath = "$.precedent"
        Next       = "Get Knowledge"
      },
      "Get Knowledge": {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.sentinel_lambdas["lambda_knowledge"].arn
          Payload = {
            "finding_type.$"  = "$.parsed_finding.Payload.finding_type"
            "resource_type.$" = "$.parsed_finding.Payload.resource_type"
          }
        }
        ResultPath = "$.knowledge"
        Next       = "Invoke Agents Pipeline"
      },
      "Invoke Agents Pipeline": {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.sentinel_lambdas["lambda_advisor"].arn
          Payload = {
            "intelligence_package": {
              "finding_details.$"       = "$.parsed_finding.Payload"
              "historical_context.$"    = "$.precedent.Payload"
              "remediation_guidelines.$" = "$.knowledge.Payload"
            },
            "finding_id.$" = "$.parsed_finding.Payload.finding_id"
          }
        }
        ResultPath = "$.advisor_output"
        Next       = "Send Telegram And Wait"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
      },
      "Send Telegram And Wait": {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        Parameters = {
          FunctionName = aws_lambda_function.sentinel_lambdas["lambda_telegram_sender"].arn
          Payload = {
            "finding.$"          = "$.parsed_finding.Payload"
            "remediation_plan.$" = "$.advisor_output.Payload.remediation_plan"
            "finding_id.$"       = "$.parsed_finding.Payload.finding_id"
            "task_token.$"       = "$$.Task.Token"
          }
        }
        ResultPath = "$.approval_result"
        Next       = "Execute Remediation"
      },
      "Execute Remediation": {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.sentinel_lambdas["lambda_executor"].arn
          Payload = {
            "finding.$"           = "$.parsed_finding.Payload"
            "approved_action.$"   = "$.approval_result.approved_action"
            "remediation_plan.$"  = "$.advisor_output.Payload.remediation_plan"
          }
        }
        ResultPath = "$.execution_result"
        End        = true
      }
    }
  })
}