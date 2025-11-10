# NOTE: HTTP APIの場合はaws_apigatewayv2_apiを使う
resource "aws_api_gateway_rest_api" "api" {
  name = "${local.project_prefix_kebab}-rest-api-gateway"
}

# Proxy resource (for /{proxy+})
resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "ANY"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  # Lambda function integration
  uri = aws_lambda_function.app_lambda.invoke_arn
  # AWS_PROXY: Lambda proxy integration
  # HTTP_PROXY: HTTP proxy integration
  # HTTP: HTTP integration
  # AWS: for AWS service
  type = "AWS_PROXY"
  # typeがHTTPまたはHTTP_PROXYの場合に、connection_type="VPC_LINK"だとプライベート統合と呼ばれる
  # 要するにVPCと接続するためにVPCリンクを使う場合の設定
  # デフォルトはINTERNETなので以下は省略可能
  connection_type = "INTERNET"
  # Lambda function can only be invoked via POST
  # refs: https://github.com/amazon-archives/aws-apigateway-importer/issues/9#issuecomment-129651005
  # TODO: Lambda統合以外の場合はまた調べないといけない
  integration_http_method = "POST"
}

# Root resource method (for /)
resource "aws_api_gateway_method" "root_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_rest_api.api.root_resource_id
  http_method             = aws_api_gateway_method.root_method.http_method
  uri                     = aws_lambda_function.app_lambda.invoke_arn
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
}


# プロキシ統合を使わないかつ、MOCKで返す場合の設定例。
# マッピングテンプレートの実装方法についても参考になる。
# for AeyeScanの設定をそのままもってきた
resource "aws_api_gateway_resource" "aeye_scan_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "aeye_activation_cc5bc50798e115eb"
}

resource "aws_api_gateway_method" "aeye_scan_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.aeye_scan_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# プロキシ統合をしない場合、マネコンのメソッドリクエスト、統合リクエストの設定もここで設定する
resource "aws_api_gateway_integration" "aeye_scan_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.aeye_scan_resource.id
  http_method = aws_api_gateway_method.aeye_scan_method.http_method
  type        = "MOCK"

  # NOTE: マネコンでMOCKのメソッドを設定すると、自動で以下の設定が入る. terraformでは明示的に定義する必要がある.
  request_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200
}
EOF
  }

  # XMLをJSONに変換する例
  #   request_templates = {
  #     "application/xml" = <<EOF
  # {
  #    "body" : $input.json('$')
  # }
  # EOF
  #   }
}


# どんな形式のレスポンスを返せるかを定義する(レスポンスの中身自体はaws_api_gateway_integration_responseで定義)
# マネコンの「メソッドレスポンス」の部分に相当
resource "aws_api_gateway_method_response" "aeye_scan_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.aeye_scan_resource.id
  http_method = aws_api_gateway_method.aeye_scan_method.http_method
  status_code = "200"
}

# どんなレスポンスを返すかを定義する
# マネコンの「統合レスポンス」の部分に相当
resource "aws_api_gateway_integration_response" "MyDemoIntegrationResponse" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.aeye_scan_resource.id
  http_method = aws_api_gateway_method.aeye_scan_method.http_method
  status_code = aws_api_gateway_method_response.aeye_scan_response.status_code
  response_templates = {
    "text/html" = <<EOF
aeye_activation_cc5bc50798e115eb
EOF
  }

  # JSONをXMLに変換する例
  #   response_templates = {
  #     "application/xml" = <<EOF
  # #set($inputRoot = $input.path('$'))
  # <?xml version="1.0" encoding="UTF-8"?>
  # <message>
  #     $inputRoot.body
  # </message>
  # EOF
  #   }
}

# --- リソースの設定おわり ---

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${data.aws_region.main.region}:${data.aws_caller_identity.self.account_id}:${aws_api_gateway_rest_api.api.id}/*/*"
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    # NOTE: The configuration below will satisfy ordering considerations,
    #       but not pick up all future REST API changes. More advanced patterns
    #       are possible, such as using the filesha1() function against the
    #       Terraform configuration file(s) or removing the .id references to
    #       calculate a hash against whole resources. Be aware that using whole
    #       resources will show a difference after the initial implementation.
    #       It will stabilize to only change when resources change afterwards.
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.resource.id,
      aws_api_gateway_method.root_method.id,
      aws_api_gateway_method.method.id,
      aws_api_gateway_integration.root_integration.id,
      aws_api_gateway_integration.integration.id,
      "1", # manual bump to force redeployment
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "main"

  # x-ray有効化
  xray_tracing_enabled = true

  depends_on = [aws_cloudwatch_log_group.api_gateway_log_group]
}

resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  # API Gatewayの命名と合わせることでロググループが自動で紐づく
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.api.id}/main"
  retention_in_days = 7
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  # すべてのリソースとメソッドに適用
  # "path1/GET" や "path1/path2/POST" のように個別指定も可能
  # 個別指定する場合は、aws_api_gateway_method_settingsリソースを複数作って対応する
  method_path = "*/*"

  settings {
    # cloud watch logs有効化
    metrics_enabled = true
    # ERROR, INFO
    logging_level = "ERROR"
    # data trace logs有効化. 基本的にoffで良さそう
    data_trace_enabled = false
    # --- thottling settings ---
    # NOTE: メソッドごとのスロットリングは上のmethod_pathで個別指定する
    # 1秒あたりの平均リクエスト数（RPS）
    throttling_rate_limit = 10
    # 短時間（約1秒以内）に許可される最大リクエスト数（スパイク対応）
    throttling_burst_limit = 30
  }
}
