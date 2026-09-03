variable "prefix" {
  description = "Name/tag prefix, app-env-regionshort (e.g. fdp-dev-euw2). Supplied by the root."
  type        = string
}

variable "region" {
  description = "AWS region this module deploys into."
  type        = string
}

variable "tags" {
  description = "Common tags applied via merge on resources that need an explicit Name."
  type        = map(string)
  default     = {}
}

variable "source_dir" {
  description = "Path to the directory holding the Lambda's Python sources."
  type        = string
}

# ---- Destination DynamoDB table (pre-existing, referenced not created) ---- #

variable "transactions_table_name" {
  description = "Name of the DynamoDB table the Lambda writes decisions to."
  type        = string
}

variable "transactions_table_arn" {
  description = "ARN of the DynamoDB table the Lambda writes decisions to."
  type        = string
}

variable "table_partition_key" {
  description = "Partition-key attribute name on the transactions table."
  type        = string
  default     = "transaction_id"
}

variable "table_sort_key" {
  description = "Sort-key attribute name on the transactions table, or empty if the table has none."
  type        = string
  default     = ""
}

# ---- Kinesis source stream ---------------------------------------------- #

variable "kinesis_stream_mode" {
  description = "Kinesis capacity mode: PROVISIONED or ON_DEMAND."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["PROVISIONED", "ON_DEMAND"], var.kinesis_stream_mode)
    error_message = "kinesis_stream_mode must be \"PROVISIONED\" or \"ON_DEMAND\"."
  }
}

variable "kinesis_shard_count" {
  description = "Shard count when kinesis_stream_mode is PROVISIONED (ignored for ON_DEMAND)."
  type        = number
  default     = 1
}

variable "kinesis_retention_hours" {
  description = "Kinesis stream data retention period, in hours (24-8760)."
  type        = number
  default     = 24

  validation {
    condition     = var.kinesis_retention_hours >= 24 && var.kinesis_retention_hours <= 8760
    error_message = "kinesis_retention_hours must be between 24 and 8760."
  }
}

# ---- Lambda sizing ----------------------------------------------------- #

variable "log_level" {
  description = "LOG_LEVEL env var for the function."
  type        = string
  default     = "INFO"
}

variable "lambda_memory_mb" {
  description = "Memory (MB) allocated to the function."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Function timeout in seconds."
  type        = number
  default     = 60
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions. -1 leaves the function unreserved."
  type        = number
  default     = -1
}

variable "lambda_log_retention_days" {
  description = "CloudWatch Logs retention for the function's log group."
  type        = number
  default     = 14
}

# ---- Kinesis event-source mapping ------------------------------------- #

variable "esm_batch_size" {
  description = "Maximum records delivered to the function per invocation."
  type        = number
  default     = 100
}

variable "esm_max_batching_window_seconds" {
  description = "Maximum seconds to buffer records before invoking (0-300)."
  type        = number
  default     = 10
}

variable "esm_parallelization_factor" {
  description = "Concurrent batches per shard (1-10)."
  type        = number
  default     = 1
}

variable "esm_starting_position" {
  description = "Where to start reading a shard: TRIM_HORIZON or LATEST."
  type        = string
  default     = "TRIM_HORIZON"

  validation {
    condition     = contains(["TRIM_HORIZON", "LATEST"], var.esm_starting_position)
    error_message = "esm_starting_position must be \"TRIM_HORIZON\" or \"LATEST\"."
  }
}

variable "esm_maximum_retry_attempts" {
  description = "Retries for a failing batch before records are dropped/sent on (-1 = infinite)."
  type        = number
  default     = 3
}

variable "esm_bisect_batch_on_function_error" {
  description = "Split a failing batch in two and retry each half, to isolate poison records."
  type        = bool
  default     = true
}

# ---- Sample rule parameters ----------------------------------------- #

variable "rule_block_amount" {
  description = "Transactions at or above this amount are BLOCKed."
  type        = number
  default     = 10000
}

variable "rule_challenge_amount" {
  description = "Transactions at or above this amount are CHALLENGEd."
  type        = number
  default     = 2000
}

variable "rule_blocked_countries" {
  description = "ISO-3166 alpha-2 country codes that force a BLOCK."
  type        = list(string)
  default     = []
}

variable "rule_high_risk_mcc" {
  description = "Merchant category codes that force a CHALLENGE."
  type        = list(string)
  default     = []
}

variable "rule_max_txns_per_account" {
  description = "More than this many transactions for one account in a single batch CHALLENGEs the extras."
  type        = number
  default     = 5
}
