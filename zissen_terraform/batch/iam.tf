# Batch用のIAMロール（サービスロール）
# AWS Batchサービス自体が引き受けるロール。
# コンピューティング環境やジョブキューの管理など、Batchがインフラを操作するために使用される。
resource "aws_iam_role" "evaluation_batch_service_role" {
  name = "my-project-evaluation-batch-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "batch.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "evaluation_batch_service_role_attachment" {
  role       = aws_iam_role.evaluation_batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# Batch用のIAMロール（ECSタスク実行ロール）
# ECSエージェント（コンテナ起動基盤）が引き受けるロール。
# コンテナ起動時にECRからDockerイメージをpullしたり、CloudWatch Logsにログを転送したりするために使用される。
# アプリケーションコードではなく、あくまでコンテナの「起動・管理」に必要な権限を持つ。
resource "aws_iam_role" "evaluation_batch_execution_role" {
  name = "my-project-evaluation-batch-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "evaluation_batch_execution_role_attachment" {
  role       = aws_iam_role.evaluation_batch_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECRへのアクセス権限を追加
resource "aws_iam_role_policy" "evaluation_batch_execution_ecr_policy" {
  name = "my-project-evaluation-batch-execution-ecr-policy"
  role = aws_iam_role.evaluation_batch_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = aws_ecr_repository.evaluation_batch.arn
      }
    ]
  })
}

# Batch用のIAMロール（ジョブロール）
# コンテナ内で実行されるアプリケーションコード（ジョブ）が引き受けるロール。
# S3へのデータ読み書きやCloudWatch Logsへのログ書き込みなど、ビジネスロジックに必要なAWSリソース操作に使用される。
resource "aws_iam_role" "evaluation_batch_job_role" {
  name = "my-project-evaluation-batch-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# ジョブロールに必要な権限を追加（S3アクセスなど必要に応じて追加）
resource "aws_iam_role_policy" "evaluation_batch_job_policy" {
  name = "my-project-evaluation-batch-job-policy"
  role = aws_iam_role.evaluation_batch_job_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.evaluation_bucket.arn,
          "${aws_s3_bucket.evaluation_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.batch.arn,
          "${aws_cloudwatch_log_group.batch.arn}:*"
        ]
      }
    ]
  })
}
