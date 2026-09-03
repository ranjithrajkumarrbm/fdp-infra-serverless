###############################################################################
# Root configuration for the FDP serverless transaction processor.
#
# Kinesis (transaction stream) -> Lambda (sample GOOD/CHALLENGE/BLOCK rules)
# -> DynamoDB (fdp-<env>-euw2-transactions).
#
# Region is fixed. `var.environment` selects one of the local config sets and
# every resource is named/tagged from a computed prefix:
#
#   prefix = "<app_name>-<env_name>-<region_short_name>"   e.g. fdp-dev-euw2
###############################################################################

variable "environment" {
  description = "Which local config set to deploy. One of: dev, prod."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

locals {
  # ---- Fixed identity ---------------------------------------------------- #
  app_name = "fdp"
  region   = "eu-west-2" # London

  region_short_names = {
    "eu-west-2" = "euw2"
    "eu-west-1" = "euw1"
    "us-east-1" = "use1"
  }
  region_short = local.region_short_names[local.region]

  # ---- Per-environment config sets (identical keys in both) ------------- #
  env_configs = {
    dev = {
      env_name  = "dev"
      log_level = "DEBUG"

      # Destination DynamoDB table (pre-existing, not managed by this repo).
      transactions_table_name = "fdp-dev-euw2-transactions"
      transactions_table_arn  = "arn:aws:dynamodb:eu-west-2:861477414666:table/fdp-dev-euw2-transactions"
      table_partition_key     = "transactionId" # HASH key on the table
      table_sort_key          = "customerId"    # RANGE key on the table

      # Kinesis source stream.
      kinesis_stream_mode     = "PROVISIONED"
      kinesis_shard_count     = 1
      kinesis_retention_hours = 24

      # Lambda sizing.
      lambda_memory_mb            = 256
      lambda_timeout_seconds      = 60
      lambda_reserved_concurrency = -1 # unreserved
      lambda_log_retention_days   = 14

      # Kinesis event-source mapping.
      esm_batch_size                     = 100
      esm_max_batching_window_seconds    = 10
      esm_parallelization_factor         = 1
      esm_starting_position              = "TRIM_HORIZON"
      esm_maximum_retry_attempts         = 3
      esm_bisect_batch_on_function_error = true

      # Sample rule parameters.
      rule_block_amount         = 10000
      rule_challenge_amount     = 2000
      rule_blocked_countries    = ["KP", "IR", "SY", "CU"]
      rule_high_risk_mcc        = ["7995", "6051", "4829"] # gambling, quasi-cash, wire transfer
      rule_max_txns_per_account = 5
    }

    prod = {
      env_name  = "prod"
      log_level = "INFO"

      transactions_table_name = "fdp-prod-euw2-transactions"
      transactions_table_arn  = "arn:aws:dynamodb:eu-west-2:861477414666:table/fdp-prod-euw2-transactions"
      table_partition_key     = "transactionId" # HASH key on the table
      table_sort_key          = "customerId"    # RANGE key on the table

      kinesis_stream_mode     = "ON_DEMAND"
      kinesis_shard_count     = 1 # ignored in ON_DEMAND mode
      kinesis_retention_hours = 168

      lambda_memory_mb            = 512
      lambda_timeout_seconds      = 120
      lambda_reserved_concurrency = 20
      lambda_log_retention_days   = 90

      esm_batch_size                     = 200
      esm_max_batching_window_seconds    = 5
      esm_parallelization_factor         = 4
      esm_starting_position              = "TRIM_HORIZON"
      esm_maximum_retry_attempts         = 5
      esm_bisect_batch_on_function_error = true

      rule_block_amount         = 10000
      rule_challenge_amount     = 2000
      rule_blocked_countries    = ["KP", "IR", "SY", "CU"]
      rule_high_risk_mcc        = ["7995", "6051", "4829"]
      rule_max_txns_per_account = 5
    }
  }

  env    = local.env_configs[var.environment]
  prefix = "${local.app_name}-${local.env.env_name}-${local.region_short}"

  common_tags = {
    Application = local.app_name
    Environment = local.env.env_name
    Region      = local.region
    ManagedBy   = "terraform"
    Repository  = "fdp-infra-serverless"
  }
}

module "transaction_processor" {
  source = "./modules/transaction-processor"

  prefix = local.prefix
  region = local.region
  tags   = local.common_tags

  source_dir = "${path.module}/src"

  transactions_table_name = local.env.transactions_table_name
  transactions_table_arn  = local.env.transactions_table_arn
  table_partition_key     = local.env.table_partition_key
  table_sort_key          = local.env.table_sort_key

  kinesis_stream_mode     = local.env.kinesis_stream_mode
  kinesis_shard_count     = local.env.kinesis_shard_count
  kinesis_retention_hours = local.env.kinesis_retention_hours

  log_level                   = local.env.log_level
  lambda_memory_mb            = local.env.lambda_memory_mb
  lambda_timeout_seconds      = local.env.lambda_timeout_seconds
  lambda_reserved_concurrency = local.env.lambda_reserved_concurrency
  lambda_log_retention_days   = local.env.lambda_log_retention_days

  esm_batch_size                     = local.env.esm_batch_size
  esm_max_batching_window_seconds    = local.env.esm_max_batching_window_seconds
  esm_parallelization_factor         = local.env.esm_parallelization_factor
  esm_starting_position              = local.env.esm_starting_position
  esm_maximum_retry_attempts         = local.env.esm_maximum_retry_attempts
  esm_bisect_batch_on_function_error = local.env.esm_bisect_batch_on_function_error

  rule_block_amount         = local.env.rule_block_amount
  rule_challenge_amount     = local.env.rule_challenge_amount
  rule_blocked_countries    = local.env.rule_blocked_countries
  rule_high_risk_mcc        = local.env.rule_high_risk_mcc
  rule_max_txns_per_account = local.env.rule_max_txns_per_account
}
