# ============================================================
# Slack 通知構成メモ
# SNS → AWS Chatbot → Slack の通知パイプライン
# + EventBridge による Batch ジョブ失敗の即時検知
# ============================================================

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "slack_notification" {
  name = "${var.name_prefix}-slack-notification-topic"
}

# SNS トピックポリシー
# ・デフォルトではアカウントオーナーのみ許可
# ・aws_sns_topic_policy を設定するとデフォルトポリシーが完全に上書きされるため、
#   アカウントオーナーの Statement も忘れず含める
# ・CloudWatch Alarm は IAM 認証情報で動くため明示不要
# ・EventBridge は events.amazonaws.com サービスプリンシパルで動くため明示が必要
resource "aws_sns_topic_policy" "slack_notification" {
  arn = aws_sns_topic.slack_notification.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # アカウントオーナーへのデフォルト権限（上書きで消えないよう明示）
      {
        Sid    = "__default_statement_ID"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish",
          "SNS:Receive",
        ]
        Resource = aws_sns_topic.slack_notification.arn
        Condition = {
          StringEquals = {
            "AWS:SourceOwner" = data.aws_caller_identity.current.account_id
          }
        }
      },
      # EventBridge → SNS への Publish を許可
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.slack_notification.arn
      }
    ]
  })
}


# Chatbot が CloudWatch を読み取るための IAM ロール
resource "aws_iam_role" "chatbot_role" {
  name = "${var.name_prefix}-ChatbotRoleForSlack"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "chatbot.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "chatbot_policy" {
  role       = aws_iam_role.chatbot_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# Chatbot 本体
# logging_level:
#   "ERROR" → Chatbot の動作エラーを CloudWatch Logs に記録（障害調査に有用）
#   "NONE"  → ログなし（コストゼロ、シンプル）
resource "aws_chatbot_slack_channel_configuration" "this" {
  configuration_name = "${var.name_prefix}-slack-error-notification"
  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id
  iam_role_arn       = aws_iam_role.chatbot_role.arn
  sns_topic_arns     = [aws_sns_topic.slack_notification.arn]
  logging_level      = "ERROR"
}


