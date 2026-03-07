
# DynamoDB StreamとLambdaのEvent Source Mapping
resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn = aws_dynamodb_table.app_db.stream_arn
  function_name    = aws_lambda_function.stream_lambda.arn

  # DynamoDB Stream or Kinesis Stream専用の設定
  starting_position = "LATEST"
  # DynamoDB Stream or Kinesis Stream専用の設定
  parallelization_factor = 1
  # DynamoDB Stream or Kinesis Stream or Kafka専用の設定
  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.dlq.arn
    }
  }

  batch_size = 100
  # batch_sizeが1より大きい場合に最大何秒待つか
  maximum_batching_window_in_seconds = 10

  maximum_retry_attempts = 3


  # Insertイベントのみ処理する
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT"]
      })
    }
  }
}


# SQSとLambdaのEvent Source Mapping
resource "aws_lambda_event_source_mapping" "jobmiru_v2_notify_user_sqs" {
  event_source_arn = aws_sqs_queue.jobmiru_v2_notify_queue.arn
  function_name    = aws_lambda_function.jobmiru_v2_notify_user.arn

  # とても勘違いしがちだが、SQSはLambdaにバッチでメッセージを渡す。1件ずつ処理したい場合はbatch_sizeを1にする必要がある。
  batch_size = 1

  scaling_config {
    # 2以上にする必要がある。
    maximum_concurrency = 3
  }
}
