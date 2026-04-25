resource "aws_cloudwatch_log_group" "sf_logs" {
  name              = "/aws/vendedlogs/states/${var.project_name}-orchestrator-log"
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
    Comment = "CloudSentinel AI Orchestrator: Supervisor analyzes, Advisor remediates."
    StartAt = "Invoke Supervisor Agent"
    States = {
      "Invoke Supervisor Agent" = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          "FunctionName" = aws_lambda_function.sentinel_lambdas["lambda_invoker"].arn
          "Payload" = {
            "AgentId"      = aws_bedrockagent_agent.supervisor.id
            # SỬA LỖI TẠI ĐÂY: Dùng .agent_alias_id thay vì .id
            "AgentAliasId" = aws_bedrockagent_agent_alias.supervisor_prod.agent_alias_id
            "SessionId.$"  = "$.id"
            "InputText.$"  = "States.Format('REGION: {}. EVENT_ID: {}. FINDING_DETAIL: {}', $.region, $.id, States.JsonToString($.detail))"
          }
        }
        ResultPath = "$.supervisor_result"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Next = "Prepare Intelligence Report"
      }

      "Prepare Intelligence Report" = {
        Type = "Pass"
        Parameters = {
          "finding_id.$"          = "$.id"
          "intelligence_report.$" = "States.StringToJson($.supervisor_result.Payload.Completion)"
        }
        Next = "Invoke Advisor Agent"
      }

      "Invoke Advisor Agent" = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          "FunctionName" = aws_lambda_function.sentinel_lambdas["lambda_invoker"].arn
          "Payload" = {
            "AgentId"      = aws_bedrockagent_agent.advisor.id
            # SỬA LỖI TẠI ĐÂY: Dùng .agent_alias_id thay vì .id
            "AgentAliasId" = aws_bedrockagent_agent_alias.advisor_prod.agent_alias_id
            "SessionId.$"  = "$.finding_id"
            "InputText.$"  = "States.JsonToString($.intelligence_report)"
          }
        }
        ResultPath = "$.advisor_result"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Next = "Save Report to S3"
      }

      "Save Report to S3" = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          "FunctionName" = aws_lambda_function.sentinel_lambdas["lambda_saver"].arn
          "Payload" = {
            "finding_id.$"     = "$.finding_id"
            "report_content.$" = "$.advisor_result.Payload.Completion"
            "metadata" = {
              "timestamp" = "$$.State.EnteredTime"
              "status"    = "AWAITING_REVIEW"
            }
          }
        }
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
          IntervalSeconds = 2
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        End = true
      }
    }
  })
}