resource "aws_secretsmanager_secret" "oauth_client_secret" {
  name        = "/${local.project_prefix_kebab}/oauth-client-secrets"
  description = "Secret containing RDS credentials for ${local.project_prefix_kebab}"
}
