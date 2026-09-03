###############################################################################
# Kinesis stream carrying raw transactions into the processor.
###############################################################################

resource "aws_kinesis_stream" "transactions" {
  name = "${var.prefix}-transactions"

  # shard_count is required by the provider but must be null for ON_DEMAND.
  shard_count      = var.kinesis_stream_mode == "PROVISIONED" ? var.kinesis_shard_count : null
  retention_period = var.kinesis_retention_hours

  stream_mode_details {
    stream_mode = var.kinesis_stream_mode
  }

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = merge(var.tags, { Name = "${var.prefix}-transactions" })
}
