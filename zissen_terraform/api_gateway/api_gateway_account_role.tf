# api gatewayからCloudWatch Logsへログを出力するためのIAMロールの設定
# refs: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_account
# この設定値はRegion-Wideなので注意. 
# というかaccount唯一のbase repositoryとかで設定したほうがたぶんいい。
resource "aws_api_gateway_account" "account" {
  cloudwatch_role_arn = aws_iam_role.gateway_role.arn
}


# --- Attach CloudWatch policy to the role ---
resource "aws_iam_role" "gateway_role" {
  name = "${local.project_prefix_kebab}-apigw-account-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "gateway_policy" {
  name = "${local.project_prefix_kebab}-apigw-account-policy"
  role = aws_iam_role.gateway_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}


