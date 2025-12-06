resource "aws_ecs_cluster" "example" {
  name = "example"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "this" {
  count              = 1
  cluster_name       = aws_ecs_cluster.this[0].name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # FARGATEメイン、FARGATE_SPOTをサブとして使用
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 1
    weight            = 4
  }

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    base              = 0
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "example" {
  family = "example"
  cpu    = "256"
  memory = "512"
  # fargateの場合はawsvpcを指定する
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = jsonencode(yamldecode(file("./container_definitions.yaml")))
  # タスク実行ロール
  execution_role_arn = module.ecs_task_execution_role.iam_role_arn
  # TODO: ここにタスクロールの設定できるらしい
}

resource "aws_ecs_service" "example" {
  name            = "example"
  cluster         = aws_ecs_cluster.example.arn
  task_definition = aws_ecs_task_definition.example.arn
  # タスクの数
  desired_count    = 2
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  # --- デプロイメント設定 ---
  # １つめ：デプロイメント中に実行できるタスクの最大パーセンテージ(デフォルトは200%)
  # ２つめ：デプロイメント中に維持すべき健全なタスクの最小パーセンテージ(デフォルトは100%)
  # 普通のローリングアップデート: 200, 50の組み合わせ(バランスがとれている)
  # ブルーグリーンぽいアップデート: 200, 100の組み合わせ(新しいのを起動しきってから古いのを落とす)
  # 高速デプロイ: 200, 0の組み合わせ(既存を落としつつ新しいのを起動するので早いが、ダウンタイムあり)  
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # タスク起動時のヘルスチェック猶予時間。デフォルトは0秒。
  health_check_grace_period_seconds = 60

  # タスク定義やサービス設定に変更がない場合でもデプロイを行う
  # デフォルトはfalse, 必要なときにtrueにして、不要になったらfalseに戻す運用がよいらしい
  force_new_deployment = false

  # サービスのデプロイが完了するまでterraformが待機するか
  # 開発環境であればデプロイ時間短縮のためfalseでもよいらしい
  wait_for_steady_state = true

  # タスクにExecできるようにする。本番環境ではfalseにして必要なときだけtrueにする
  enable_execute_command = true

  # --- service connect ---
  # client側 (gatewayなど)
  # service_connect_configuration {
  #   enabled   = true
  #   namespace = aws_service_discovery_http_namespace.namespace.name
  #   log_configuration {
  #     log_driver = "awslogs"
  #     options = {
  #       awslogs-group         = aws_cloudwatch_log_group.ecs.name
  #       awslogs-region        = var.aws_region
  #       awslogs-stream-prefix = "app-name"
  #     }
  #   }
  # }

  # server側 (apiなど)
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.namespace.name
    log_configuration {
      log_driver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app-name"
      }
    }

    # This setting needs to be configured based on the portMappings setting in the task definition.
    service {
      port_name = "http"
      client_alias {
        port     = 8080
        dns_name = "api-service-alias"
      }
    }
  }

  # --- タグまわり ---
  # サービス名、クラスター名などのAWS管理タグを自動的に付与
  enable_ecs_managed_tags = true
  # サービスに付いているタグをタスクにも伝搬
  propagate_tags = "SERVICE"
  network_configuration {
    assign_public_ip = false
    security_groups  = [module.nginx_sg.security_group_id]
    subnets = [
      aws_subnet.private_0.id,
      aws_subnet.private_1.id,
    ]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.example.arn
    container_name   = "example"
    container_port   = 80
  }

  # terraformで差分更新しない
  # APP側でタスク定義を更新する運用の場合はこれを設定すべき！！
  lifecycle {
    ignore_changes = [task_definition]
  }
}

module "nginx_sg" {
  source      = "../network/security_group"
  name        = "nginx-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = [aws_vpc.example.cidr_block]
}


resource "aws_cloudwatch_log_group" "for_ecs" {
  name = "/ecs/example"
  # ログの保存期間
  retention_in_days = 180
}

# service connect用のnamespace
resource "aws_service_discovery_http_namespace" "namespace" {
  name = "service-name-prd-namespace"
}

# --- タスク実行ロール ---

# Managed policyをdata resourceで取得
data "aws_iam_policy" "ecs_task_execution_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution" {
  # 既存のポリシーを継承する
  source_policy_documents = [data.aws_iam_policy.ecs_task_execution_role_policy.policy]

  # 追加で付けるポリシー
  # ここではSSMパタメータストアの参照に必要な権限
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameters", "kms:Decrypt"]
    resources = ["*"]
  }
}

module "ecs_task_execution_role" {
  source = "../iam_role"
  name   = "ecs-task-execution"
  # タスク実行ロールの場合はここをecs-tasks.amazonaws.comにする
  identifier = "ecs-tasks.amazonaws.com"
  policy     = data.aws_iam_policy_document.ecs_task_execution.json
}
