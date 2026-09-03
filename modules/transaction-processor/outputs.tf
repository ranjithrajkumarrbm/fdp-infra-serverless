output "lambda_function_name" {
  description = "Name of the transaction-processor Lambda function."
  value       = aws_lambda_function.processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the transaction-processor Lambda function."
  value       = aws_lambda_function.processor.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role."
  value       = aws_iam_role.lambda.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch Logs group for the function."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis transaction stream."
  value       = aws_kinesis_stream.transactions.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis transaction stream."
  value       = aws_kinesis_stream.transactions.arn
}

output "event_source_mapping_uuid" {
  description = "UUID of the Kinesis -> Lambda event-source mapping."
  value       = aws_lambda_event_source_mapping.kinesis.uuid
}

output "transactions_table_name" {
  description = "DynamoDB table decisions are written to."
  value       = var.transactions_table_name
}
