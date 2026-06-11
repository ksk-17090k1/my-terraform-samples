# CloudFront requires ACM certificates in us-east-1

# base_dns.tfと同様
# regionだけus-east-1必須なので注意
resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us_east_1
  domain_name       = local.hosted_zone_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# base_dns.tfと同様
resource "aws_route53_record" "cloudfront_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = local.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# base_dns.tfと同様
resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in aws_route53_record.cloudfront_cert_validation : record.fqdn]
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.system_name}-${local.environment}-frontend"
}


# cloudfront用のs3に対しての身分証明書てきなもの
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.system_name}-${local.environment}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# バケットポリシーでCloudFrontからのアクセスを許可する
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

# キャッシュ無しの設定
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# 静的ファイル配信に最適化されたキャッシュ設定
# 静的ファイルのキャッシュ、Gzip/Brotli圧縮などが有効化される
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# ユーザーのリクエストにある クッキー・クエリパラメータ・ヘッダー をそのまま ALB に転送します。ただし Host ヘッダーだけは除外します
# （CloudFront独自のドメインではなく ALB のドメインを使わせるため）。
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ブラウザからは https://example.com/api/users と叩くが、バックエンド ALB には /users として転送するための処理
# Cloudfront Functionというエッジで動作する超軽量JavaScript関数を定義
resource "aws_cloudfront_function" "strip_api_prefix" {
  name    = "${local.system_name}-${local.environment}-strip-api-prefix"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOF
    function handler(event) {
      var request = event.request;
      request.uri = request.uri.replace(/^\/api/, '') || '/';
      return request;
    }
  EOF
}

# Cloud Front本体
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [local.hosted_zone_name]

  # 2つのOrigin(転送先)を定義

  # S3への転送
  origin {
    origin_id                = "s3-frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # ALBへの転送
  origin {
    origin_id   = "alb-backend"
    domain_name = aws_lb.main_app.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # 特定のCludFrontからのリクエストのみをBackend APIで許可するためのカスタムヘッダー
    # 認証なしのサイトを公開するときのベストプラクティスになっている
    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.cloudfront_origin_verify.result
    }
  }

  # パスパターンの設定
  ordered_cache_behavior {
    target_origin_id = "alb-backend"
    path_pattern     = "/api/*"
    # HTTPでアクセスされても自動的にHTTPSにリダイレクトする
    viewer_protocol_policy = "redirect-to-https"

    # 転送を許可するHTTPメソッド
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]

    # キャッシュ対象とするメソッド(キャッシュするわけではない)
    cached_methods = ["GET", "HEAD"]
    # キャッシュ対象のメソッドをどうキャッシュするかの設定
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id

    # リクエスト情報をどう転送するかの設定
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id

    # CloudFront Functionの設定
    function_association {
      # "viewer-request" は「ユーザーからリクエストが来た直後、転送する前」
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.strip_api_prefix.arn
    }
  }

  # ordered_cache_behaviorがどれもマッチしない場合の設定
  # ordered_cache_behaviorで定義されていないすべてのパスがマッチする。当然ルートパス/も。
  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]

    cached_methods  = ["GET", "HEAD"]
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # -- SPA client-side routing ---
  # SPAのreact-routerだと例えばabout/index.htmlというファイルは存在せず、
  # ユーザーがAboutボタンをクリック -> レンダリングと同時にURLに/aboutを付与(リクエストは発生せず) という挙動をする。
  # そのため、ユーザーが直接URLとして/aboutにアクセスするとそのファイルは無いのでS3から403/404が帰る問題がある。
  # これを解決するために、403/404であれば200に変換して/index.htmlをブラウザに返す、という設定をする。
  # （ブラウザには/index.htmlを返すが、URLは/aboutのまま、というのがポイント）
  # この状態になると、Reactはパスの/aboutを見て再レンダリングし、正しいAboutページが表示される。
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      # none: 全世界からアクセス可, blacklist: 指定した国からのアクセス不可, whitelist: 指定した国からのアクセスのみ可
      restriction_type = "none"
    }
  }

  # SSL証明書の設定
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}


# A(ALIAS)レコード
resource "aws_route53_record" "frontend" {
  zone_id = local.hosted_zone_id
  name    = local.hosted_zone_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
