# NOTE: EventBridgeは以前CloudWatch Eventsと呼ばれていた
# terraformでは後方互換のためにcloud watch eventsという名前のままのリソースになっている
resource "aws_cloudwatch_event_rule" "example_batch" {
  name        = "example-batch"
  description = "とても重要なバッチ処理です"

  # S3バケットへのputをトリガーにする場合の例
  event_pattern = jsonencode({
    "source" : ["aws.s3"],
    "detail-type" : ["Object Created"],
    "detail" : {
      "bucket" : {
        "name" : [aws_s3_bucket.sagemaker_bucket.bucket]
      },
      "object" : {
        "key" : [{
          "suffix" : ".csv"
        }]
      }
    }
  })
}

# S3からトリガーするにはこのresourceも必要らしい。
resource "aws_s3_bucket_notification" "sagemaker_bucket_notification" {
  bucket      = aws_s3_bucket.sagemaker_bucket.id
  eventbridge = true
}


