
# Rest APIで、AWSサービス統合でSfnを呼び出す例。
# GCPのpub/subのpushでapi gatewayがpostされ、sfnに繋がる実装をしていた

# NOTE: プロキシ統合を使っていないので、aws_api_gateway_method_response, aws_api_gateway_integration_response
# のリソースも明示的に作る必要があることに注意。(これはaeye scanの例と同様。)


resource "aws_api_gateway_resource" "gcs_pubsub_receiver_notify" {
  rest_api_id = aws_api_gateway_rest_api.gcs_pubsub_receiver.id
  parent_id   = aws_api_gateway_rest_api.gcs_pubsub_receiver.root_resource_id
  path_part   = "notify"
}

resource "aws_api_gateway_method" "gcs_pubsub_receiver_post" {
  rest_api_id   = aws_api_gateway_rest_api.gcs_pubsub_receiver.id
  resource_id   = aws_api_gateway_resource.gcs_pubsub_receiver_notify.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "gcs_pubsub_receiver_sfn" {
  rest_api_id = aws_api_gateway_rest_api.gcs_pubsub_receiver.id
  resource_id = aws_api_gateway_resource.gcs_pubsub_receiver_notify.id
  http_method = aws_api_gateway_method.gcs_pubsub_receiver_post.http_method

  # AWSサービス統合で直接 Step Functions を呼び出す
  # ここがこのメモファイルの肝！
  uri                     = "arn:aws:apigateway:${data.aws_region.jobmiru_v2.name}:states:action/StartExecution"
  type                    = "AWS"
  integration_http_method = "POST"
  credentials             = aws_iam_role.jobmiru_v2_apigw_sfn.arn


  # NOTE: # Pub/Sub push body: { "message": { "attributes": { "objectId": "user_input/jobs_xxx.csv", ... }, ... }, ... }
  request_templates = {
    "application/json" = <<-VTL
      {
        "stateMachineArn": "${aws_sfn_state_machine.gcs_sensor.arn}"
      }
    VTL
  }
}

resource "aws_api_gateway_method_response" "gcs_pubsub_receiver_200" {
  rest_api_id = aws_api_gateway_rest_api.gcs_pubsub_receiver.id
  resource_id = aws_api_gateway_resource.gcs_pubsub_receiver_notify.id
  http_method = aws_api_gateway_method.gcs_pubsub_receiver_post.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "gcs_pubsub_receiver_200" {
  rest_api_id = aws_api_gateway_rest_api.gcs_pubsub_receiver.id
  resource_id = aws_api_gateway_resource.gcs_pubsub_receiver_notify.id
  http_method = aws_api_gateway_method.gcs_pubsub_receiver_post.http_method
  status_code = aws_api_gateway_method_response.gcs_pubsub_receiver_200.status_code

  response_templates = {
    "application/json" = "{}"
  }

}
