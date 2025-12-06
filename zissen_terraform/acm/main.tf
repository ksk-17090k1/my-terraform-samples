
# 竹村さんが作った証明書を作ってS3に格納するmodule
# 解読はできていない。。。

# S3 for certificate storage
resource "aws_s3_bucket" "certificate_bucket" {
  bucket        = "${local.base_name}-${var.environment}-certificate-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "certificate_bucket_policy" {
  bucket = aws_s3_bucket.certificate_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement : [{
      Effect = "Allow",
      Principal = {
        AWS = aws_iam_role.certificate_s3_access_role.arn
      },
      Action = "s3:*",
      Resource = [
        "arn:aws:s3:::${local.base_name}-${var.environment}-certificate-bucket",
        "arn:aws:s3:::${local.base_name}-${var.environment}-certificate-bucket/*"
      ]
    }]
  })
}

resource "aws_iam_policy" "cert_s3_access_policy" {
  name        = "cert-s3-access-policy"
  description = "Allow access to S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.certificate_bucket.arn,
          "${aws_s3_bucket.certificate_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "certificate_s3_access_role" {
  name = "certificate-s3-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "certificate_s3_access_role_policy_attachment" {
  role       = aws_iam_role.certificate_s3_access_role.name
  policy_arn = aws_iam_policy.cert_s3_access_policy.arn
}

data "aws_acm_certificate" "imported_certificate" {
  depends_on = [terraform_data.import_acm_certificate]
  domain     = "${local.base_name}-${var.environment}.${var.common_name}"
  statuses   = ["ISSUED"]
  key_types  = ["RSA_4096"]
}

resource "terraform_data" "create_certificate_and_upload_s3" {
  depends_on = [aws_s3_bucket_policy.certificate_bucket_policy]
  provisioner "local-exec" {
    command = <<EOT
      openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -keyout private-key.pem -out certificate.pem -subj "/C=JP/ST=Tokyo/L=Tokyo/CN=${local.base_name}-${var.environment}.${var.common_name}" -addext "subjectAltName = DNS:${local.base_name}-${var.environment}.${var.common_name},DNS:localhost" > /dev/null 2>&1
      openssl x509 -in certificate.pem -out certificate.crt > /dev/null 2>&1
      aws s3 cp certificate.pem s3://${local.base_name}-${var.environment}-certificate-bucket/certificate.pem 
      aws s3 cp private-key.pem s3://${local.base_name}-${var.environment}-certificate-bucket/private-key.pem 
      aws s3 cp certificate.crt s3://${local.base_name}-${var.environment}-certificate-bucket/certificate.crt 
      rm -f certificate.pem private-key.pem certificate.crt
    EOT
  }
}

resource "terraform_data" "import_acm_certificate" {
  depends_on = [terraform_data.create_certificate_and_upload_s3]
  provisioner "local-exec" {
    command = <<EOT
      aws s3 cp s3://${local.base_name}-${var.environment}-certificate-bucket/certificate.pem /tmp/certificate.pem
      aws s3 cp s3://${local.base_name}-${var.environment}-certificate-bucket/private-key.pem /tmp/private-key.pem
      aws acm import-certificate --certificate fileb:///tmp/certificate.pem --private-key fileb:///tmp/private-key.pem --tags Key=Environment,Value=${var.environment} Key=CommonName,Value=${local.base_name}-${var.environment}.${var.common_name}
      rm -f /tmp/certificate.pem /tmp/private-key.pem
    EOT
  }
}
