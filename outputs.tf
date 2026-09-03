output "resource_prefix" {
  description = "Computed name/tag prefix for this environment (app-env-regionshort)."
  value       = local.prefix
}

output "lambda_function_name" {
  description = "Name of the transaction-processor Lambda function."
  value       = module.transaction_processor.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the transaction-processor Lambda function."
  value       = module.transaction_processor.lambda_function_arn
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis stream that feeds the processor."
  value       = module.transaction_processor.kinesis_stream_name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis stream that feeds the processor."
  value       = module.transaction_processor.kinesis_stream_arn
}

output "transactions_table_name" {
  description = "DynamoDB table the processor writes decisions to."
  value       = module.transaction_processor.transactions_table_name
}
