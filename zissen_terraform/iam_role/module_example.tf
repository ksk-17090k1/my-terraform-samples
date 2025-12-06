variable "name" {}
# ここにもaws_iam_policy_documentのdata sourceが入る
variable "policy" {}
variable "identifier" {}

resource "aws_iam_role" "default" {
  name = var.name
  # NOTE: ここにjsonencode()で直接jsonを書くこともできる。
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# assume role policyの定義

# NOTE: aws_iam_policy_documentのdata sourceだけ他のdata sourceと挙動が異なる。
# 外部からリソースを取得するのではなく、完全にただのJSONを生成するだけの役割を持つ。
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = [var.identifier]
    }
  }
}

# policy documentをiam policyに変換
resource "aws_iam_policy" "default" {
  name = var.name
  # NOTE: ここにjsonencode()で直接jsonを書くこともできる。
  policy = var.policy
}


# NOTE: aws_iam_policy_attachmentは使ってはいけない！！！！
resource "aws_iam_role_policy_attachment" "default" {
  role = aws_iam_role.default.name
  # NOTE: ここに直接managed policyのarnを書くこともできる。
  #       ex. "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  # むしろ、マネージドのポリシーを付けたいだけならそっちのがいいかも。
  policy_arn = aws_iam_policy.default.arn
}

output "iam_role_arn" {
  value = aws_iam_role.default.arn
}

output "iam_role_name" {
  value = aws_iam_role.default.name
}
