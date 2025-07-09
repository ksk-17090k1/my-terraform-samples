
resource "aws_ssm_parameter" "db_username" {
  name        = "/db/username"
  value       = "root"
  type        = "String"
  description = "データベースのユーザー名"
}


# Secure String
# 最初はダミーのuninitializedをセットして、CLI経由で本当な値をセットする！！
resource "aws_ssm_parameter" "db_password" {
  name        = "/db/password"
  value       = "uninitialized"
  type        = "SecureString"
  description = "データベースのパスワード"

  # 本当の値はCLIでセットするので、差分を無視する
  lifecycle {
    ignore_changes = [value]
  }
}

// NOTE: ECSのタスク定義のjsonで以下のようにするとパラメータストアから値を参照できる
# "secrets": [
#     {
#     "name": "DB_USERNAME",
#     "valueFrom": "/db/username"
#     },
#     {
#     "name": "DB_PASSWORD",
#     "valueFrom": "/db/password"
#     }
# ],
