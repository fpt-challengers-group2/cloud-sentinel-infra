output "s3_bucket_name" {
  value = aws_s3_bucket.reports.id
}

output "step_function_arn" {
  value = aws_sfn_state_machine.orchestrator.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.incident_history.name
}