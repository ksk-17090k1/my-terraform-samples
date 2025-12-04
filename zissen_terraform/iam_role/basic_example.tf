
# metaflowのterraform moduleから持ってきたもの。


# aws_iam_policy_document (data source): policyのjsonを作成する
# aws_iam_policy: policyを作成する (policyのところはdata sourceか直でjsonで書く)
# aws_iam_role: roleを作成する (assume role policyはdata sourceか直でjsonで書く)
# aws_iam_role_policy_attachment: roleとpolicyを紐付ける  (grant_xxxx_policyみたいな命名にすることが多い)

# aws_iam_role_policy: roleにinline policyを追加する (基本使わないほうが良さそう)
# aws_iam_policy_attachment: 絶対に使ってはいけない

# 流派としては、aws_iam_policy_document()を使うかjsonencode()を使うかで分かれそう
# jsonencode()でいいかなという気がしている。

data "aws_iam_policy_document" "batch_execution_role_assume_role" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]

    effect = "Allow"

    principals {
      identifiers = [
        "batch.amazonaws.com",
      ]
      type = "Service"
    }
  }
}

resource "aws_iam_role" "batch_execution_role" {
  name        = "my-batch-execution-role"
  description = "This role is passed to AWS Batch as a `service_role`. This allows AWS Batch to make calls to other AWS services on our behalf."

  assume_role_policy = data.aws_iam_policy_document.batch_execution_role_assume_role.json
}

data "aws_iam_policy_document" "iam_pass_role" {
  statement {
    actions = [
      "iam:PassRole"
    ]

    effect = "Allow"

    resources = [
      "*"
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "ec2.amazonaws.com.cn", "ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "custom_access_policy" {
  statement {
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceAttribute",
    ]

    effect = "Allow"

    resources = [
      "*"
    ]
  }
}

resource "aws_iam_role_policy" "grant_iam_pass_role" {
  name   = "iam_pass_role"
  role   = aws_iam_role.batch_execution_role.name
  policy = data.aws_iam_policy_document.iam_pass_role.json
}

resource "aws_iam_role_policy" "grant_custom_access_policy" {
  name   = "custom_access"
  role   = aws_iam_role.batch_execution_role.name
  policy = data.aws_iam_policy_document.custom_access_policy.json
}


resource "aws_iam_role_policy_attachment" "grant_batch_service_role_policy" {
  role       = aws_iam_role.batch_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}
