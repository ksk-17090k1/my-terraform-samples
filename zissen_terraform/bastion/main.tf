
data "aws_iam_policy" "ec2_for_ssm" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


data "aws_iam_policy_document" "ec2_for_ssm" {
  source_policy_documents = [data.aws_iam_policy.ec2_for_ssm.policy]

  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      # S3とCloudWatch Logsの書き込み権限
      "s3:PutObject",
      "logs:PutLogEvents",
      "logs:CreateLogStream",
      # ECRへの参照権限(任意)
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      # SSMパラメータストアの参照権限(任意)
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "kms:Decrypt",
    ]
  }
}

# EC2用に使うロールの宣言
module "ec2_for_ssm_role" {
  source     = "../iam_role"
  name       = "ec2-for-ssm"
  identifier = "ec2.amazonaws.com"
  policy     = data.aws_iam_policy_document.ec2_for_ssm.json
}

# EC2は直接ロールをアタッチできないという特殊仕様があるため、まずはinstance profileとRoleを紐づける
resource "aws_iam_instance_profile" "ec2_for_ssm" {
  name = "ec2-for-ssm"
  role = module.ec2_for_ssm_role.iam_role_name
}

# --- Bastion EC2 ---

# NOTE: このEC2はSSH接続しない前提なので、キーペアは作成していない。
resource "aws_instance" "example_for_operation" {
  # Amazon Linux 2のAMIを指定
  ami           = "ami-0c3fd0f5d33134a76"
  instance_type = "t3.micro"
  # Instance ProfileをEC2にアタッチする
  iam_instance_profile = aws_iam_instance_profile.ec2_for_ssm.name
  # subnetはリソース作るのがめんどいので一旦コメントアウト
  #   subnet_id            = aws_subnet.private_0.id
  user_data = file("./user_data.sh")
}

# オペレーションログ(Session Managerの操作ログ)用のS3バケット
resource "aws_s3_bucket" "operation" {
  bucket = "operation-pragmatic-terraform"
}

resource "aws_s3_bucket_lifecycle_configuration" "operation" {
  bucket = aws_s3_bucket.operation.id

  rule {
    id     = "delete_old_objects"
    status = "Enabled"

    # すべてのオブジェクトに適用するための空フィルタ
    filter {}

    expiration {
      days = 180
    }
  }
}

# オペレーションログ(Session Managerの操作ログ)をCloudWatch Logsに出力
resource "aws_cloudwatch_log_group" "operation" {
  name              = "/operation"
  retention_in_days = 180
}

# SSM Documentの作成
# シェル経由でEC2に接続する際に、--document-nameでこのドキュメントを指定する
# ただし、nameを"SSM-SessionManagerRunShell"にしていると省略しても参照してくれる。
resource "aws_ssm_document" "session_manager_run_shell" {
  name = "SSM-SessionManagerRunShell"
  # Session Managerのドキュメントの場合は"Session", "JSON"を指定する
  document_type   = "Session"
  document_format = "JSON"

  # Session Managerの操作ログをS3とCloudWatch Logsに出力する設定
  content = <<EOF
  {
    "schemaVersion": "1.0",
    "description": "Document to hold regional settings for Session Manager",
    "sessionType": "Standard_Stream",
    "inputs": {
      "s3BucketName": "${aws_s3_bucket.operation.id}",
      "cloudWatchLogGroupName": "${aws_cloudwatch_log_group.operation.name}"
    }
  }
EOF
}



output "operation_instance_id" {
  value = aws_instance.example_for_operation.id
}
