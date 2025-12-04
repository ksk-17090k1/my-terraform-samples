resource "aws_dynamodb_table" "jobmiru_v2_job_items" {
  name = "${local.project_prefix}-db-job-items"
  # ここデフォルトだとPROVISIONEDになってるので注意！！！
  billing_mode = "PAY_PER_REQUEST"
  table_class  = "STANDARD"
  hash_key     = "job_id"
  range_key    = "branch_name"

  tags = {
    Name = "${local.project_prefix}-db-job-items"
  }

  attribute {
    name = "job_id"
    type = "N"
  }

  attribute {
    name = "branch_name"
    type = "S"
  }

  ttl {
    attribute_name = "unixtimeTtl"
    enabled        = true
  }

  # stream
  stream_enabled = true
  # KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES
  stream_view_type = "NEW_IMAGE"

  deletion_protection_enabled = true
}




# DynamoDB StreamとLambdaのEvent Source Mapping
resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn  = aws_dynamodb_table.app_db.stream_arn
  function_name     = aws_lambda_function.stream_lambda.arn
  starting_position = "LATEST"

  batch_size                         = 100
  maximum_batching_window_in_seconds = 10

  maximum_retry_attempts = 3

  parallelization_factor = 1

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.dlq.arn
    }
  }

  # Insertイベントのみ処理する
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT"]
      })
    }
  }
}
