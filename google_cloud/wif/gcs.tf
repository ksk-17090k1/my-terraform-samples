resource "google_storage_bucket" "csv_bucket" {
  name     = "sample-csv-bucket"
  location = "ASIA-NORTHEAST1"
  versioning {
    enabled = true
  }

  # 公開アクセスの防止
  public_access_prevention = "enforced"

  force_destroy = false

  # ACLはlegacyなのでtrueにすべき
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}
