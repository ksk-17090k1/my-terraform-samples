# terraformのバージョン, providerを指定
terraform {
  required_version = "1.12.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# AWS プロバイダーの設定
provider "aws" {
  region = "ap-northeast-1"
}

resource "null_resource" "example" {

  # terraform destroyで削除されないようにする保険
  # このリソース定義全体を削除してapplyすると削除できてしまうので注意！！
  lifecycle {
    prevent_destroy = true
  }
}

# --- 三項演算子 ---
variable "env" {}

resource "aws_instance" "example" {
  ami = "ami-0c3fd0f5d33134a76"
  # 三項演算子(ternary operator)
  instance_type = var.env == "prod" ? "t3.large" : "t3.micro"
}

#  --- Count ---
# 一気にリソースを複数つくれる！
# NOTE: count=0にすればリソースが作られないので、三項演算子と組み合わせて汎用性の高いモジュールを作るときに便利(本の19.3参照)
resource "aws_vpc" "example" {
  count      = 3
  cidr_block = "10.0.${count.index}.0/24"
}

# --- 良く使われるData Resource ---

# AWSのアカウントID
data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

# 現在のAWSリージョン
data "aws_region" "current" {}

output "region_name" {
  value = data.aws_region.current.name
}

# AZをリストで取得
data "aws_availability_zones" "available" {
  state = "available"
}

output "availability_zones" {
  value = data.aws_availability_zones.available.names
}

# サービスアカウント
# たとえばALBのサービスアカウントを取得する
data "aws_elb_service_account" "current" {}

output "alb_service_account_id" {
  value = data.aws_elb_service_account.current.id
}


# --- random provider ---

# 生成した文字列は、random_string.password.resultでアクセスできる
resource "random_string" "password" {
  length = 32
  # DBのマスターパスワード等では一部の特殊文字が使えないのでfalseにする
  special = false
}


# IAM Role Moduleの使用
module "describe_regions_for_ec2" {
  source     = "./iam_role"
  name       = "describe-regions-for-ec2"
  identifier = "ec2.amazonaws.com"
  policy     = data.aws_iam_policy_document.ec2_describe_regions.json
}

data "aws_iam_policy_document" "ec2_describe_regions" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeRegions"
    ]
    resources = ["*"]
  }
}

