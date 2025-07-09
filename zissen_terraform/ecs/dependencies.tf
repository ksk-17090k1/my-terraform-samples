
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
  # AWSのDNSサーバによる名前解決を有効に
  enable_dns_support = true
  # VPC内のリソースにパブリックDNSホスト名を自動的に割り当てる
  enable_dns_hostnames = true

  tags = {
    Name = "example"
  }
}


# --- public subnet (Multi-AZ) ---
resource "aws_subnet" "public_0" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}



resource "aws_route_table_association" "public_0" {
  subnet_id      = aws_subnet.public_0.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# --- private subnet (Multi-AZ) ---

resource "aws_subnet" "private_0" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.65.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.66.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = false
}

# NOTE: 依存するInternet GatewayはMulti-AZの場合でも単一！
# ただし、EIPとNat GatewayはAZごとに作成する必要がある！（実は１つでもいけるが冗長性のため）

resource "aws_eip" "nat_gateway_0" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.example]
}

resource "aws_eip" "nat_gateway_1" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.example]
}

resource "aws_nat_gateway" "nat_gateway_0" {
  allocation_id = aws_eip.nat_gateway_0.id
  subnet_id     = aws_subnet.public_0.id
  depends_on    = [aws_internet_gateway.example]
}

resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_gateway_1.id
  subnet_id     = aws_subnet.public_1.id
  depends_on    = [aws_internet_gateway.example]
}
resource "aws_route_table" "private_0" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route" "private_0" {
  route_table_id         = aws_route_table.private_0.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_0.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route" "private_1" {
  route_table_id         = aws_route_table.private_1.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_1.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private_0" {
  subnet_id      = aws_subnet.private_0.id
  route_table_id = aws_route_table.private_0.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1.id
}


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



# 既にあるホストゾーンを取得
# data "aws_route53_zone" "example" {
#   name = "example.com"
# }

# 新しいホストゾーンを作成
resource "aws_route53_zone" "example" {
  name = "test.example.com"
}

# DNSレコード
resource "aws_route53_record" "example" {
  zone_id = aws_route53_zone.example.zone_id
  name    = aws_route53_zone.example.name
  # A / CNAME / MX / TXT / SRV / AAAA / SPF
  type = "A"

  # このAliasブロックを指定すると、AレコードはALIASレコードになる！
  # ALIASはAWS特有のレコード。DNSからみると単なるAレコードと同じ。
  # Aレコードとの差異は、AWSネットワーク内での最適化、ヘルスチェック、IPが変わってもOK、という利点がある
  alias {
    name = aws_lb.example.dns_name
    # ここにはLBやCloudFrontを指定できる
    zone_id                = aws_lb.example.zone_id
    evaluate_target_health = true
  }
}

# SSL証明書
resource "aws_acm_certificate" "example" {
  # domain名 (*.example.comのようにするとワイルドカード証明書になる)
  domain_name = aws_route53_record.example.name
  # ここに任意の個数のサブドメインを指定できる
  subject_alternative_names = []
  # DNS検証かe-mail検証を選択
  validation_method = "DNS"

  lifecycle {
    # リソースを作成してから、既存リソースを削除する
    # サービス影響最小化のため。
    create_before_destroy = true
  }
}

# 検証用DNSレコード
# NOTE: subject_alternative_namesに何か指定した場合はその分のDNSレコードも必要
resource "aws_route53_record" "example_certificate" {
  for_each = {
    for dvo in aws_acm_certificate.example.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  zone_id = aws_route53_zone.example.id
  ttl     = 60
}

# SSL証明書の検証が完了するまで待機
# このリソースは特殊で、特に何かリソースが作成されるわけではない。待機するだけ。
resource "aws_acm_certificate_validation" "example" {
  certificate_arn = aws_acm_certificate.example.arn
  validation_record_fqdns = [
    for record in aws_route53_record.example_certificate : record.fqdn
  ]
}



output "domain_name" {
  value = aws_route53_record.example.name
}
