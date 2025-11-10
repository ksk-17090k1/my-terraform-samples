resource "aws_dynamodb_table" "jobmiru_v2_job_items" {
  name         = "${local.project_prefix}-db-job-items"
  # ここデフォルトだとPROVISIONEDになってるので注意！！！
  billing_mode = "PAY_PER_REQUEST"
  table_class  = "STANDARD"
  hash_key     = "job_id"
  range_key    = "branch_name"

  tags = {
    Name = "${local.project_prefix}-db-job-items"
  }

  attribute {
    name = "job_id"
    type = "N"
  }

  attribute {
    name = "branch_name"
    type = "S"
  }

  ttl {
    attribute_name = "unixtimeTtl"
    enabled        = true
  }

  deletion_protection_enabled = true
}
