resource "google_iam_workload_identity_pool_provider" "jobmiru_processor_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.aws_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "jobmiru-processor-prd-provider"
  display_name                       = "jobmiru-processor AWS IdP"

  # AWS プロバイダとして設定
  aws {
    account_id = local.aws_account_id_generative_ai_prd
  }

  # 属性条件: 受け入れる AWS 主体を制限
  # 特定アカウントの assumed-role のみを許可
  attribute_condition = "attribute.aws_role == '${local.aws_iam_role_name_jobmiru_processor}'"

  # 属性マッピング: AWS 側の情報を GCP 側の属性に変換
  attribute_mapping = {
    "google.subject"        = "assertion.arn"
    "attribute.aws_account" = "assertion.account"
    "attribute.aws_role"    = "assertion.arn.extract('assumed-role/{role}/')"
  }
}

# 借用先の IAM Service Account の作成
resource "google_service_account" "jobmiru_processor_wif_sa" {
  account_id   = "jobmiru-processor-prd-wif"
  display_name = "Access from AWS by Workload Identity Federation"
}

# IAM Service Account の権限借用の許可 (workloadIdentityUser)
resource "google_service_account_iam_member" "jobmiru_processor_allow_impersonation" {
  service_account_id = google_service_account.jobmiru_processor_wif_sa.name
  role               = "roles/iam.workloadIdentityUser"

  # AWS 側の IAM Role の名前で制限
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.aws_pool.name}/attribute.aws_role/${local.aws_iam_role_name_jobmiru_processor}"
}

# Vertex AI 管理者の権限付与
resource "google_project_iam_member" "vertex_ai_admin" {
  project = local.project
  role    = "roles/aiplatform.admin"
  member  = "serviceAccount:${google_service_account.jobmiru_processor_wif_sa.email}"
}

