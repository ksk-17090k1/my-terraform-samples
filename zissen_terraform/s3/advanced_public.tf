# --- publicなバケット ---
resource "aws_s3_bucket" "public" {
  bucket = "public-pragmatic-terraform"
}


# ACLを設定してpublicにする
resource "aws_s3_bucket_acl" "public" {
  bucket = aws_s3_bucket.public.id
  acl    = "public-read"
}


# CORS設定
resource "aws_s3_bucket_cors_configuration" "public" {
  bucket = aws_s3_bucket.public.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["https://example.com"]
    max_age_seconds = 3000
  }
}

