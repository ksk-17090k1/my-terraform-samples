# Batch Compute Environment (Fargate)
resource "aws_batch_compute_environment" "evaluation_batch" {

  # compute environmentは更新はできず削除->作成の流れになる。
  # その際にterraformで更新しようとすると既存リソースと競合してエラーになるらしく、
  # name_prefixをnameの代わりに使う方がいい、という記述もある。実際やったが正しそう。
  # refs: https://github.com/lvgs-aiml-engineering/aiml-terraform-aws-metaflow/blob/downstream/main/modules/computation/batch.tf
  # 一応更新は update_policy を指定すると対応できるぽいが、applyが複数回必要になるので確かにprefixの方が良さそう。
  name_prefix = "my-project-evaluation-batch-compute-env-"

  type = "MANAGED"


  compute_resources {

    # --- fargateの設定 ---

    # "EC2", "SPOT", "FARGATE", "FARGATE_SPOT"のいずれかを指定。
    # spot instance使えるのアツいな
    type = "FARGATE"

    # min_vcpus, desired_vcpusはfargateでは指定しない。
    max_vcpus = 16


    # network
    subnets = [
      var.subnet_private_01_id,
      var.subnet_private_02_id
    ]
    security_group_ids = [
      aws_security_group.evaluation_batch.id
    ]

    # --- EC2の設定(Fargateの場合は不要) ---
    # あんまりちゃんと理解できてない

    instance_role = ""
    instance_type = ["c4.large", "c4.xlarge", "c4.2xlarge", "c4.4xlarge", "c4.8xlarge"]

    # 最適なインスタンスタイプのインスタンスが十分に割り当てられない場合に、コンピューティング リソースに割り当てるための戦略
    allocation_strategy = "BEST_FIT_PROGRESSIVE"

    # max_vcpus = 16
    # min_vcpus = 0
    # コンピューティング環境におけるEC2 vCPUの必要数
    desired_vcpus = 8

    # TODO:  launch_template, placement_groupの使い分けが良く分からん

  }

  # AWS Batchのサービスロールを付与
  service_role = aws_iam_role.evaluation_batch_service_role.arn


  lifecycle {
    /* From here https://github.com/terraform-providers/terraform-provider-aws/issues/11077#issuecomment-560416740
       helps with "modifying" batch compute environments which requires creating new ones and deleting old ones
       as no inplace modification can be made
    */
    create_before_destroy = true
  }

  depends_on = [aws_iam_role_policy_attachment.evaluation_batch_service_role_attachment]
}

# Batch Job Queue
# AWS Batchでは、キューに複数のEnvが紐づく、という構成になっている。
# Envに複数のキューが紐づくという構成ではないので注意！
resource "aws_batch_job_queue" "evaluation_batch" {
  name  = "my-project-evaluation-batch-job-queue"
  state = "ENABLED"

  # 複数のキューが存在する場合にどれを優先して使うかを決める値
  # 複数のキューが同一のEnvを指定している場合に活きる設定値
  # リアルタイム処理用のキューと、バッチ処理用のキューを用意し同一のEnvを指定し、
  # リアルタイム用のキューの優先度を上げる、などの使い方ができる。
  priority = 1

  # どのEnvを優先して使うかを決める値
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.evaluation_batch.arn
  }

  # こんな感じで足せる
  compute_environment_order {
    order               = 2
    compute_environment = aws_batch_compute_environment.test_environment_2.arn
  }
}

# Batch Job Definition
resource "aws_batch_job_definition" "evaluation_batch" {
  name = "my-project-evaluation-batch-job"

  # "container" or "multinode"
  type = "container"

  # "EC2" or "FARGATE"
  platform_capabilities = ["FARGATE"]

  # いわゆるタスク定義の内容が入る
  container_properties = jsonencode({
    image = "${aws_ecr_repository.evaluation_batch.repository_url}:latest"

    resourceRequirements = [
      {
        type  = "VCPU"
        value = tostring(var.batch_job_vcpu)
      },
      {
        type  = "MEMORY"
        value = tostring(var.batch_job_memory)
      }
    ]

    # ECSエージェントに付与するBatch Execution Roleを付与
    executionRoleArn = aws_iam_role.evaluation_batch_execution_role.arn
    # 実行されるアプリケーションに付与されるJob Roleを付与
    jobRoleArn = aws_iam_role.evaluation_batch_job_role.arn

    networkConfiguration = {
      assignPublicIp = "DISABLED"
    }

    fargatePlatformConfiguration = {
      platformVersion = "LATEST"
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "evaluation-batch"
      }
    }

    environment = [
      {
        name  = "APP_ENV"
        value = var.environment
      }
    ]
  })

  retry_strategy {
    # 1 ~ 10
    attempts = 2
  }

  timeout {
    # min value is 60 
    attempt_duration_seconds = 3600
  }
}


# --- CloudWatch Logs group for Batch ---
resource "aws_cloudwatch_log_group" "batch" {
  name              = "/aws/batch/my-project-evaluation-batch"
  retention_in_days = 30
}


## --- ECR Repository for Evaluation Batch ---
resource "aws_ecr_repository" "evaluation_batch" {
  name                 = "my-project-evaluation-batch"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_lifecycle_policy" "features_fetch_batch" {
  repository = aws_ecr_repository.evaluation_batch.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 2
        description  = "タグ付きイメージを最新10件のみ保持"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = [""]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# --- security groups ---
resource "aws_security_group" "evaluation_batch" {
  name        = "my-project-evaluation-batch-sg"
  description = "Security group for AWS Batch evaluation batch compute environment"
  vpc_id      = var.vpc_id

  tags = {
    Name = "my-project-evaluation-batch-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "evaluation_batch_egress_all" {
  security_group_id = aws_security_group.evaluation_batch.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
