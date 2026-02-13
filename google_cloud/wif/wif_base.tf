resource "google_iam_workload_identity_pool" "aws_pool" {
  workload_identity_pool_id = "aiml-base-prd-aws-pool"
  display_name              = "aiml-base-prd-aws-pool"
  description               = "Pool for AWS workload federation for aiml-base-prd"
}


