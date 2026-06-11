resource "aws_sagemaker_domain" "sagemaker_domain" {
  domain_name = "${local.name_prefix}-sagemaker-domain"
  auth_mode   = "IAM"
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution_role.arn
  }
}

resource "aws_sagemaker_user_profile" "sagemaker_user_profile" {
  domain_id         = aws_sagemaker_domain.sagemaker_domain.id
  user_profile_name = "${local.name_prefix}-sagemaker-user-profile"
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "${local.name_prefix}-sagemaker-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      },
    ]
  })
}



# SageMaker MLflow操作に必要な権限を定義したポリシー
resource "aws_iam_policy" "sagemaker_mlflow_permissions" {
  name        = "${local.name_prefix}-sagemaker-mlflow-policy"
  description = "Permissions for SageMaker MLflow operations"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "sagemaker-mlflow:*",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}


resource "aws_iam_role_policy_attachment" "sagemaker_processing_ecr" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "sagemaker_mlflow_permissions_attachment" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = aws_iam_policy.sagemaker_mlflow_permissions.arn
}


# MLflow managed by SageMakerを使うためのリソース
resource "aws_sagemaker_mlflow_app" "model_experiment" {
  name               = "model-experiment"
  role_arn           = "arn:aws:iam::${data.aws_caller_identity.self.account_id}:role/${local.project_prefix_kebab}-sagemaker-execution-role"
  artifact_store_uri = "s3://${local.project_prefix_kebab}-sagemaker-bucket/mlflow"
}
