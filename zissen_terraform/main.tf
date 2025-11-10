

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

  # stateの保存先を設定
  backend "s3" {
    bucket = "tfstate-pragmatic-terraform"
    # TODO: このkeyの命名規則どうしてんだろ
    key    = "example/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

# AWS プロバイダーの設定
provider "aws" {
  region = "ap-northeast-1"

  # default tagsは設定しといた方がいい
  default_tags {
    tags = {
      Environment  = "stg"
      Project      = "my-project"
      ManagedBy    = "terraform"
      Organization = "your-org"
    }
  }
}

# ====== 超基本 ======

# --- variable ---
# NOTE: TF_VAR_example_instance_type という環境変数を作るとterraformが勝手に上書きする
# コマンドライン引数的に上書きもできる

# var.example_instance_type でアクセスできる
variable "example_instance_type" {
  default = "t3.micro"
}

# --- local variable ---
# local.example_instance_type でアクセスできる
locals {
  example_instance_type = "t3.micro"
}

# --- data source ---
# data.aws_ami.recent_amazon_linux.image_id でアクセスできる
data "aws_ami" "recent_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# --- Moduleの使用 ---
module "describe_regions_for_ec2" {
  source     = "./iam_role"
  name       = "describe-regions-for-ec2"
  identifier = "ec2.amazonaws.com"
  policy     = data.aws_iam_policy_document.ec2_describe_regions.json
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

# --- Lifecycle ---

resource "null_resource" "example" {

  # terraform destroyで削除されないようにする保険
  # このリソース定義全体を削除してapplyすると削除できてしまうので注意！！
  lifecycle {
    prevent_destroy = true
  }
}


# --- 良く使われるData Source ---

# IAMポリシーを取得
# NOTE: aws_iam_policy_documentのdata sourceだけ他のdata sourceと挙動が異なる。
# 外部からリソースを取得するのではなく、完全にただのJSONを生成するだけの役割を持つ。
data "aws_iam_policy_document" "ec2_describe_regions" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeRegions"
    ]
    resources = ["*"]
  }
}

# 既存のIAMマネージドポリシーを取得
data "aws_iam_policy" "jobmiru_v2_vpc_access_lambda" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  # 以下でも書ける
  # name        = "AWSLambdaBasicExecutionRole"
  # path_prefix = "/service-role/"
}

# AWSのアカウントID
# data.aws_caller_identity.self.account_id でアクセスできる
data "aws_caller_identity" "self" {}


# 現在のAWSリージョン
# data.aws_region.main.region でアクセスできる
data "aws_region" "main" {}


# AZをリストで取得
# data.aws_availability_zones.available.names でアクセスできる
data "aws_availability_zones" "available" {
  state = "available"
}

# サービスアカウント
# たとえばALBのサービスアカウントを取得する
# data.aws_elb_service_account.main.id でアクセスできる
data "aws_elb_service_account" "main" {}


# SSMパラメータストア
# たとえば以下であれば aws_ssm_parameter.subnet_id.value でアクセスできる
data "aws_ssm_parameter" "subnet_id" {
  name = "/staging/public/subnet/id"
}

# tagで検索
data "aws_subnet" "public_staging" {
  tags = {
    Environment   = "Staging"
    Accessibility = "Public"
  }
}

# filterで絞り込む
data "aws_subnet" "public_staging" {
  filter {
    name = "vpc-id"
    # こんな感じで絞り込みに他のdata sourceを使える
    values = [data.aws_vpc.staging.id]
  }

  filter {
    name   = "cidr-block"
    values = ["192.168.0.0/24"]
  }
}

# --- route53 ---
data "aws_route53_zone" "inside" {
  zone_id = "Z064454120TUJ17G7VNI"
}




# --- random provider ---

# 生成した文字列は、random_string.password.resultでアクセスできる
resource "random_string" "password" {
  length = 32
  # DBのマスターパスワード等では一部の特殊文字が使えないのでfalseにする
  special = false
}


# ====== 組み込み関数 ======

# yaml
resource "aws_ecs_task_definition" "example" {
  family = "example"
  memory = "512"
  # yamlをjsonに変換してcontainer_definitionsに渡す
  container_definitions = jsonencode(yamldecode(file("./cd.yaml")))
}

# compact, concat, try

# compact: リストからnullや空文字を除外する
# concat: リストを結合する
# try: エラーが出たら空文字を返す
resource "aws_lb" "this" {

  security_groups = compact(
    concat(
      var.custom_security_group_ids,
      [
        try(aws_security_group.this[0].id, "")
      ]
    )
  )

  # merge: マップを結合する
  # coalesce: 最初にnullでない値を返す
  tags = merge(
    var.load_balancer_custom_tags,
    {
      Name = coalesce(var.load_balancer_custom_tag_name, local.elb_tag_name)
    }
  )

}
