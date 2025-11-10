
resource "aws_cloudwatch_log_group" "log_group" {
  # NOTE: ここをLambdaの関数名に合わせると、勝手に関数と紐づく仕様。そうなんだ。
  name              = "/aws/lambda/sample-lambda-validate-jobs-csv"
  retention_in_days = 90
}

resource "aws_lambda_function" "jobmiru_v2_validate_jobs_csv" {
  function_name = "sample-lambda-validate-jobs-csv"
  # roleはservice principalを"lambda.amazonaws.com"にして作る
  role          = aws_iam_role.jobmiru_v2_lambda_execution.arn
  image_uri     = "${module.jobmiru_v2_ecr_repository.url}:validate_jobs_csv-latest"
  package_type  = "Image"
  architectures = ["x86_64"]
  timeout       = 900
  memory_size   = 1024

#   vpc_config {
#     subnet_ids         = var.subnet_ids
#     security_group_ids = [module.jobmiru_v2_security_group_lambda.id]
#   }

  environment {
    variables = {
      LOG_LEVEL           = "INFO"
      STAGE               = "dummy"
    }
  }

  lifecycle {
    ignore_changes = [image_uri]
  }
  # TODO: x-rayの有効化

  # Ensure log group exists before function
  depends_on = [aws_cloudwatch_log_group.log_group]

}