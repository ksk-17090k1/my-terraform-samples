# NOTE: EventBridgeは以前CloudWatch Eventsと呼ばれていた
# terraformでは後方互換のためにcloud watch eventsという名前のままのリソースになっている
module "ecs_events_role" {
  source     = "../iam_role"
  name       = "ecs-events"
  identifier = "events.amazonaws.com"
  policy     = data.aws_iam_policy.ecs_events_role_policy.policy
}


resource "aws_cloudwatch_event_rule" "example_batch" {
  name        = "example-batch"
  description = "とても重要なバッチ処理です"
  # cronの他にrateも使える
  schedule_expression = "cron(*/2 * * * ? *)"
}


# NOTE: ECSのevent targetの例はecs/にある。
