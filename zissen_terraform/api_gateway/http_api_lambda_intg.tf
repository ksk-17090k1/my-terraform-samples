resource "aws_apigatewayv2_api" "jobmiru_v2_web_api" {
  name = "${local.project_prefix}-apigw-web-api"
  # HTTP, WEBSOCKET
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "jobmiru_v2_web_api" {
  api_id = aws_apigatewayv2_api.jobmiru_v2_web_api.id

  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.jobmiru_v2_web_api.invoke_arn

  # VPC_LINK, INTERNET, default is INTERNET
  # ALBとの統合のように、VPC_LINKを明示的に使うとき以外はINTERNETのままでOK
  connection_type = "INTERNET"
  # Lambda関数は実はPOST以外受け付けないのでPOST
  integration_method = "POST"

  # デフォルトはHTTPなら30s, WebSocketなら29s
  timeout_milliseconds = 30000
}

resource "aws_apigatewayv2_route" "jobmiru_v2_web_api" {
  api_id = aws_apigatewayv2_api.jobmiru_v2_web_api.id
  # the route key can be either $default, or a combination of an HTTP method and resource path, for example, GET /pets.
  # REST APIの/{proxy+}のようなプロキシリソースを作る場合は、$defaultを指定する
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.jobmiru_v2_web_api.id}"
}

resource "aws_apigatewayv2_stage" "jobmiru_v2_web_api" {
  api_id = aws_apigatewayv2_api.jobmiru_v2_web_api.id
  # stage nameを$defaultにするとstage名のパスをURLに含めない仕様になる！！！しらん！
  # 後段にlambda web-adapterを噛ませているときはstage名がパスに入ると邪魔なので、$defaultにしたほうがいい。
  name = "$default"
  # デフォルトはfalse
  auto_deploy = true

  // スロットリングの設定
  default_route_settings {
    // バーストリミット
    throttling_burst_limit = 10
    // 秒間リクエスト数の上限
    throttling_rate_limit = 5

    # メトリクスを取得するようにする(cloudwatchの費用はかかるとのこと)
    detailed_metrics_enabled = true
  }
}

resource "aws_lambda_permission" "jobmiru_v2_web_api_apigw" {
  statement_id  = "AllowHTTPAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jobmiru_v2_web_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.jobmiru_v2_web_api.execution_arn}/*/*"
}
