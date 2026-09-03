###############################################################################
# Transaction-processor Lambda: Kinesis -> sample rules -> DynamoDB.
#
# Build step: `data.archive_file` zips the Python sources in `var.source_dir`
# on every plan/apply. `source_code_hash` is derived from that zip, so any
# change to the sources redeploys the function on the next apply. CI also runs
# `scripts/package.sh` as an explicit build stage (syntax gate + artifact).
###############################################################################

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/${var.prefix}-txn-processor.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.prefix}-txn-processor"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(var.tags, { Name = "/aws/lambda/${var.prefix}-txn-processor" })
}

resource "aws_lambda_function" "processor" {
  function_name = "${var.prefix}-txn-processor"
  description   = "Classifies Kinesis transactions as GOOD/CHALLENGE/BLOCK and writes results to DynamoDB."
  role          = aws_iam_role.lambda.arn

  runtime = "python3.12"
  handler = "handler.handler"

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      LOG_LEVEL                 = var.log_level
      TRANSACTIONS_TABLE_NAME   = var.transactions_table_name
      TABLE_PARTITION_KEY       = var.table_partition_key
      TABLE_SORT_KEY            = var.table_sort_key
      RULE_BLOCK_AMOUNT         = tostring(var.rule_block_amount)
      RULE_CHALLENGE_AMOUNT     = tostring(var.rule_challenge_amount)
      RULE_BLOCKED_COUNTRIES    = join(",", var.rule_blocked_countries)
      RULE_HIGH_RISK_MCC        = join(",", var.rule_high_risk_mcc)
      RULE_MAX_TXNS_PER_ACCOUNT = tostring(var.rule_max_txns_per_account)
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = merge(var.tags, { Name = "${var.prefix}-txn-processor" })
}

resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn  = aws_kinesis_stream.transactions.arn
  function_name     = aws_lambda_function.processor.arn
  starting_position = var.esm_starting_position
  enabled           = true

  batch_size                         = var.esm_batch_size
  maximum_batching_window_in_seconds = var.esm_max_batching_window_seconds
  parallelization_factor             = var.esm_parallelization_factor
  maximum_retry_attempts             = var.esm_maximum_retry_attempts
  bisect_batch_on_function_error     = var.esm_bisect_batch_on_function_error

  # Return only the failed records from the handler so Kinesis retries just
  # those instead of the whole batch.
  function_response_types = ["ReportBatchItemFailures"]
}
