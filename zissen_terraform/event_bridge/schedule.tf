resource "aws_scheduler_schedule" "jobmiru_v2_gather_ra_request" {
  name                         = "sample-pj-schedule-gather-ra-request"
  schedule_expression          = "cron(*/15 0-12 ? * MON-FRI *)"
  schedule_expression_timezone = "UTC"

  # scheduleした時間からどれだけズレてもよいか。
  # OFF: ちょうどに実行
  # FLEXIBLE: ちょうどに実行することを目指すが、多少のズレは負荷分散のため許容する
  flexible_time_window {
    mode = "FLEXIBLE"
    # 5分のズレは許容する
    maximum_window_in_minutes = 5

  }

  target {
    arn = aws_sfn_state_machine.jobmiru_v2_gather_ra_request.arn
    # schedulerがtargetを呼び出す際に使うIAMロール
    role_arn = aws_iam_role.jobmiru_v2_eventbridge_scheduler_sfn.arn
  }
}
