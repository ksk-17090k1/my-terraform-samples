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


# ============================================================
# GCS → Pub/Sub 通知設定
# ============================================================

# NOTE: 将来的にpub_sub.tfとかに移したほうがいいかも

# これはgoogle cloudが用意する、AWSでいうGCSのリソースポリシーをつけるリソースのようなもの。
data "google_storage_project_service_account" "gcs_account" {}

# topic作成
resource "google_pubsub_topic" "csv_upload_notification" {
  name = "sample-pj-topic-csv-upload"
}

# GCSサービスアカウントが Pub/Sub トピックへ publish できるよう権限を付与する
# AWSのリソースポリシー的な感じのもの
resource "google_pubsub_topic_iam_member" "gcs_publisher" {
  topic  = google_pubsub_topic.csv_upload_notification.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

# GCSのアップロードイベントを Pub/Sub トピックに送信する
# NOTE: この設定はコンソールでは見えないので注意。
# refs: https://docs.cloud.google.com/storage/docs/reporting-changes?hl=ja#console_1
resource "google_storage_notification" "csv_upload" {
  bucket = google_storage_bucket.csv_bucket.name
  # prefixを指定
  object_name_prefix = "user_input/"

  event_types    = ["OBJECT_FINALIZE"]
  payload_format = "JSON_API_V1"

  topic = google_pubsub_topic.csv_upload_notification.id

  depends_on = [google_pubsub_topic_iam_member.gcs_publisher]
}

resource "google_service_account" "pubsub_push" {
  account_id   = "sample-pj-pubsub-push"
  display_name = "Pub/Sub push service account for gcs-sensor"
}

# NOTE: subscriptionはpushとpullがあり、これはpush
# pullのほうはまだよく分かってない。
resource "google_pubsub_subscription" "csv_upload_push" {
  name  = "sample-pj-sub-csv-upload-push"
  topic = google_pubsub_topic.csv_upload_notification.name

  push_config {
    push_endpoint = "${aws_api_gateway_stage.gcs_pubsub_receiver.invoke_url}/notify"

    # この設定でJWTトークンをAuthorizationヘッダーに乗せることができる
    # これをやると、リクエスト受け取った側でJWTの検証をして、APIに認証をかけることができる。
    oidc_token {
      service_account_email = google_service_account.pubsub_push.email
    }
  }

  expiration_policy {
    # サブスクリプションは31日アクションがないと削除されるので、ttlを空にして無期限にする。
    # https://zenn.dev/o2wsu9/articles/0e3bb4077a7eaa
    ttl = ""
  }

  # pushが失敗した際に自動で行われるretryの設定
  retry_policy {
    # 最初のretryまで最小何秒待つか
    # default 10s
    minimum_backoff = "10s"
    # retryの間隔は指数バックオフで増えていくので、それの最大値
    # default 600s
    maximum_backoff = "600s"
  }
}
