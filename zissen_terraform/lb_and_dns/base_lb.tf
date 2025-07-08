resource "aws_lb" "example" {
  name = "example"
  # application / network
  load_balancer_type = "application"
  # internet通信を行うか！
  internal = false
  # ITS案件生成で問題になったタイムアウトのやつ！
  idle_timeout = 60
  # 誤って削除するのを防ぐ用の設定
  enable_deletion_protection = true

  subnets = [
    aws_subnet.public_0.id,
    aws_subnet.public_1.id,
  ]

  access_logs {
    bucket  = aws_s3_bucket.alb_log.id
    enabled = true
  }

  security_groups = [
    module.http_sg.security_group_id,
    module.https_sg.security_group_id,
    module.http_redirect_sg.security_group_id,
  ]
}

# --- sg ---
module "http_sg" {
  source      = "../network/security_group"
  name        = "http-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}

module "https_sg" {
  source      = "../network/security_group"
  name        = "https-sg"
  vpc_id      = aws_vpc.example.id
  port        = 443
  cidr_blocks = ["0.0.0.0/0"]
}

module "http_redirect_sg" {
  source      = "../network/security_group"
  name        = "http-redirect-sg"
  vpc_id      = aws_vpc.example.id
  port        = 8080
  cidr_blocks = ["0.0.0.0/0"]
}

# --- ログ用のS3バケット ---
resource "aws_s3_bucket" "alb_log" {
  bucket = "alb-log-pragmatic-terraform"
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_log" {
  bucket = aws_s3_bucket.alb_log.id

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

resource "aws_s3_bucket_policy" "alb_log" {
  bucket = aws_s3_bucket.alb_log.id
  policy = data.aws_iam_policy_document.alb_log.json
}

data "aws_iam_policy_document" "alb_log" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.alb_log.id}/*"]

    principals {
      type        = "AWS"
      identifiers = ["582318560864"]
    }
  }
}

# --- リスナー ---
# HTTP
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  # HTTP / HTTPS
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これは『HTTP』です"
      status_code  = "200"
    }
  }
}

# HTTPS
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.example.arn
  # この値はおまじないらしい
  ssl_policy = "ELBSecurityPolicy-2016-08"

  # デフォルトアクション
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これは『HTTPS』です"
      status_code  = "200"
    }
  }
}


# リダイレクトのリスナー
resource "aws_lb_listener" "redirect_http_to_https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "8080"
  protocol          = "HTTP"

  # デフォルトアクション
  default_action {
    type = "redirect"

    redirect {
      port = "443"
      # この例だとリダイレクト先がHTTPSなのでHTTPSにする
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


# Target Group
resource "aws_lb_target_group" "example" {
  name = "example"
  # EC2, IP, Lambdaなどが指定できる
  target_type = "ip"
  # target_type="ip"とした場合はvpc_id, port, protocolが必要
  vpc_id = aws_vpc.example.id
  port   = 80
  # 多くの場合HTTPSの終端はALBをつかうので、ここはほぼHTTPになる
  protocol = "HTTP"
  # ターゲットの登録解除でALBが待機する秒数
  deregistration_delay = 300

  health_check {
    path = "/"
    # 正常と判断するまでの実行回数
    healthy_threshold = 5
    # 異常と判断するまでの実行回数
    unhealthy_threshold = 2
    # ヘルスチェックのタイムアウト
    timeout = 5
    # ヘルスチェックの実行間隔
    interval = 30
    # ヘルスチェックで正常と判断するレスポンスコード
    matcher = 200
    # ヘルスチェックで使うポート。
    # "traffic-port"とすると上記のターゲットグループのポートを使う
    port     = "traffic-port"
    protocol = "HTTP"
  }

  depends_on = [aws_lb.example]
}

# リスナールール
resource "aws_lb_listener_rule" "example" {
  listener_arn = aws_lb_listener.https.arn
  # 数字が小さいほど優先度が高い
  priority = 100

  # デフォルトではないアクション
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}




output "alb_dns_name" {
  value = aws_lb.example.dns_name
}
