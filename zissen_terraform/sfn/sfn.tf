resource "aws_sfn_state_machine" "jobmiru_v2_update_bq_and_sheet" {
  name     = "sample-pj-sfn-update-bq-and-sheet"
  role_arn = aws_iam_role.jobmiru_v2_sfn_execution.arn

  definition = jsonencode({
    Comment = "sync_bq_table → update_detection_sheet"
    StartAt = "SyncBqTable"
    States = {
      SyncBqTable = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.jobmiru_v2_sync_bq_table.arn
        }
        # --- retry ---
        Retry = [
          {
            # States.ALLはすべてのエラーを補足する
            # エラーは、Lambda.SdkClientException, Lambda.TooManyRequestsException, Lambda.AWSLambdaExceptionなどがある。
            ErrorEquals = ["States.ALL"]
            # 初回のリトライまでの待機時間
            IntervalSeconds = 3
            MaxAttempts     = 2
            # 2は指数バックオフを表す
            BackoffRate = 2
          }
        ]
        # --- catch(retryしてもダメなとき) ---
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyOnFailure"
          }
        ]
        Next = "UpdateDetectionSheet"
      }
      UpdateDetectionSheet = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          # スケジューラ入力から FunctionName を取得することで
          # 通常版と _with_removal 版で同一ステートマシンを共用できる
          # NOTE: keyに.$をつけると、valueがJSONPath式として評価される
          "FunctionName.$" = "$$.Execution.Input.update_detection_sheet_lambda_arn"
        }
        End = true
      }
      # --- catch後の処理 ---
      NotifyOnFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl = aws_sqs_queue.jobmiru_v2_notify_queue.url
          MessageBody = jsonencode({
            module_name = "gather_ra_request"
            message     = "処理の途中で失敗したタスクがあります\n処理名: gather_ra_request"
            can_mention = true
          })
        }
        End = true
      }
    }
  })

  # ERRORレベルのみ記録
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.my_pj_sfn_gcs_sensor.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }
}

resource "aws_cloudwatch_log_group" "my_pj_sfn_gcs_sensor" {
  name              = "/aws/states/my-pj-sfn-gcs-sensor"
  retention_in_days = 60
}


# SfnからCloudWatch Logsにログを出すには、CloudWatch Logsのリソースポリシーで明示的に許可する必要あり。
resource "aws_cloudwatch_log_resource_policy" "my_pj_sfn_log_publishing" {
  policy_name = "my-pj-sfn-log-publishing"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "states.amazonaws.com" }
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
        ]
        Resource = "*"
      }
    ]
  })
}



# map state example
resource "aws_sfn_state_machine" "job_processing" {
  name     = "sample-pj-sfn-job-processing"
  role_arn = aws_iam_role.jobmiru_v2_sfn_execution.arn

  definition = jsonencode({
    Comment = "generate_job_info → complement_job_info → make_rpa_format（全ステップ同期）"
    StartAt = "GenerateJobInfoMap"
    States = {
      GenerateJobInfoMap = {
        Type = "Map"
        # 前段からの入力をjsonと見たときに、generate_itemsというkeyのvalueをItemPathとする
        # ここは.$を付けなくてもjson pathとして解釈されるぽい。
        ItemsPath      = "$.generate_items"
        MaxConcurrency = 5
        Iterator = {
          StartAt = "GenerateJobInfo"
          States = {
            GenerateJobInfo = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.jobmiru_v2_generate_job_info.arn
                # generate_itemsの各要素をそのままLambdaのeventとして渡す($なので)
                "Payload.$" = "$"
              }
              End = true
            }
          }
        }
        # このstepの入力をそのまま次のstepとして渡す
        # これをしないとLambdaの出力がResultPathに入る。
        # このmachineではmake_format_itemsの並行数をMakeRpaFormatMap stepに伝えたいのでこうしている。
        ResultPath = null
        Next       = "ComplementJobInfo"
      }
      ComplementJobInfo = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.jobmiru_v2_complement_job_info.arn
        }
        # このstepの入力をそのまま次のstepとして渡す(理由は同上)
        ResultPath = null
        Next       = "MakeRpaFormatMap"
      }
      MakeRpaFormatMap = {
        Type           = "Map"
        ItemsPath      = "$.make_format_items"
        MaxConcurrency = 3
        Iterator = {
          StartAt = "MakeRpaFormat"
          States = {
            MakeRpaFormat = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.jobmiru_v2_make_rpa_format.arn
                "Payload.$"  = "$"
              }
              End = true
            }
          }
        }
        End = true
      }
    }
  })
}

# Sfnをevent bridge schedulerから呼び出す
resource "aws_scheduler_schedule" "job_processing_schedule" {
  name                         = "sample-pj-schedule-job-processing"
  schedule_expression          = "cron(*/15 0-12 ? * MON-FRI *)"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.job_processing.arn
    role_arn = aws_iam_role.jobmiru_v2_eventbridge_scheduler_sfn.arn
    input = jsonencode({
      # 通常、job_idなどの数でmap stateは並行数を決めるが、
      # 固定で並行数を決めたい場合はこのようにする。
      generate_items    = [{}, {}, {}, {}, {}]
      make_format_items = [{}, {}, {}]
    })
  }
}
