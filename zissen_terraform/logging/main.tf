resource "aws_s3_bucket" "cloudwatch_logs" {
  bucket = "cloudwatch-logs-pragmatic-terraform"
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudwatch_logs" {
  bucket = aws_s3_bucket.cloudwatch_logs.id

  rule {
    id     = "delete_old_objects"
    status = "Enabled"

    # すべてのオブジェクトに適用するための空フィルタ
    filter {}

    expiration {
      days = 180
    }
  }
}

# Kinesis Data FirehoseのIAMロール
data "aws_iam_policy_document" "kinesis_data_firehose" {
  statement {
    effect = "Allow"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.cloudwatch_logs.id}",
      "arn:aws:s3:::${aws_s3_bucket.cloudwatch_logs.id}/*",
    ]
  }
}

# Kinesis Data FirehoseのIAMロールの宣言
module "kinesis_data_firehose_role" {
  source     = "../iam_role"
  name       = "kinesis-data-firehose"
  identifier = "firehose.amazonaws.com"
  policy     = data.aws_iam_policy_document.kinesis_data_firehose.json
}

# 配信ストリーム作成
resource "aws_kinesis_firehose_delivery_stream" "example" {
  name = "example"
  # 昔のterraformでは"s3"を指定していたが、今は"extended_s3"を指定する必要がある
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = module.kinesis_data_firehose_role.iam_role_arn
    bucket_arn = aws_s3_bucket.cloudwatch_logs.arn
    prefix     = "ecs-scheduled-tasks/example/"
  }
}


# --- CloudWatch Logsの設定 ---
data "aws_iam_policy_document" "cloudwatch_logs" {
  # Kinesis Data Firehose操作権限
  statement {
    effect    = "Allow"
    actions   = ["firehose:*"]
    resources = ["arn:aws:firehose:ap-northeast-1:*:*"]
  }

  # Pass Roleする権限
  # なぜこれが必要か正直ちゃんとは理解してない。。。
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::*:role/cloudwatch-logs"]
  }
}


# CloudWatch LogsのIAMロールの宣言
module "cloudwatch_logs_role" {
  source     = "../iam_role"
  name       = "cloudwatch-logs"
  identifier = "logs.ap-northeast-1.amazonaws.com"
  policy     = data.aws_iam_policy_document.cloudwatch_logs.json
}

# CloudWatch Logs Subscription Filter
# つまりLog GroupからKinesisにデータを流す設定
resource "aws_cloudwatch_log_subscription_filter" "example" {
  name = "example"
  # ECSタスクのLog Groupを指定
  log_group_name = aws_cloudwatch_log_group.for_ecs_scheduled_tasks.name
  # Kinesis Data Firehoseを指定
  destination_arn = aws_kinesis_firehose_delivery_stream.example.arn
  # "[]"はフィルタせずに全てのログを流す設定
  filter_pattern = "[]"
  role_arn       = module.cloudwatch_logs_role.iam_role_arn
}

# これはダミー
resource "aws_cloudwatch_log_group" "for_ecs_scheduled_tasks" {
  name              = "/ecs-scheduled-tasks/example"
  retention_in_days = 180
}
