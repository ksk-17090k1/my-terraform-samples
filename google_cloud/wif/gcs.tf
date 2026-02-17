resource "google_storage_bucket" "csv_bucket" {
  name     = "sample-csv-bucket"
  location = "ASIA-NORTHEAST1"
  versioning {
    enabled = true
  }

  # ACLはlegacyなのでtrueにすべき
  uniform_bucket_level_access = true
  # 公開アクセスの防止
  # uniform_bucket_level_accessがtrueだとコンソールには非公開、と表示されるが、
  # 公開アクセスの防止はまた別の設定なので注意。わかりにくい。。。
  public_access_prevention = "enforced"

  force_destroy = false


  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}
