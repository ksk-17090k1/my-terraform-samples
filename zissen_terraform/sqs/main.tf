# NOTE: dlqという名前がついているが、SQS目線では通常のキュー
resource "aws_sqs_queue" "sample_queue" {
  name = "${local.project_prefix_kebab}-sample-queue"
  # キューに入ってから処理実行されるまでの時間。デフォルトは0秒
  delay_seconds = 15
  # 1024 ~ 262144 bytesを指定する。
  # デフォルトは262144 bytes (256 KiB)
  # NOTE: ただし、AWS側では2025/08に1MiBに拡張されているぽい。
  max_message_size = 256 * 1024
  # 60 ~ 1209600 秒を指定する。つまり1分から14日間。
  # デフォルトは345600秒 (4日間)
  message_retention_seconds = 60 * 60 * 24 * 3

  # この値により、SQSに対してキュー内のメッセージをデキューするリクエストが来た際、キューが空の場合の挙動が変わる。
  # 0以上、20以下の値を設定できる。
  # 0に設定すると、キューが空でも即座にレスポンスを返します。この挙動をショートポーリングと呼びます。
  # 1以上に設定すると、キューが空のときは設定した秒数だけ待ってからレスポンスを返します。この挙動をロングポーリングと呼びます。
  receive_wait_time_seconds = 10

  # 可視性タイムアウト: lambda_timeout + batch_window + 30s とすると良いらしい
  # batch_window は maximum_batching_window_in_seconds のこと
  visibility_timeout_seconds = 120 + 10 + 30

  # FIFOキューにしたい場合は以下を指定する
  # fifo_queue = true

  # 再実行に関する設定
  # redrive_policy = jsonencode({
  #   # 失敗したら以下のデッドレターキューにデータをエンキューする
  #   deadLetterTargetArn = aws_sqs_queue.dlq.arn
  #   # 最大2回まで実行する (同じメッセージを3回目に受け取ったらデッドレターキューに送る)
  #   maxReceiveCount = 2
  # })
}
