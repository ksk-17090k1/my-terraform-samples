resource "aws_ecs_cluster" "example" {
  name = "example"
}

resource "aws_ecs_task_definition" "example" {
  family = "example"
  cpu    = "256"
  memory = "512"
  # fargateの場合はawsvpcを指定する
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  # TODO: Yaml化する
  container_definitions = file("./container_definitions.json")
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
  # タスク起動時のヘルスチェック猶予時間。デフォルトは0秒。
  health_check_grace_period_seconds = 60

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
