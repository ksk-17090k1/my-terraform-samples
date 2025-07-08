
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
