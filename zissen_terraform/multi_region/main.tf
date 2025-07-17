
# aliasが無いproviderがデフォルト
provider "aws" {
  region = "ap-northeast-1"
}

# aliasがあるproviderがデフォルトではない扱いになる
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}


resource "aws_vpc" "virginia" {
  # 明示的にproviderを指定する
  provider   = aws.virginia
  cidr_block = "192.168.0.0/16"
}

resource "aws_vpc" "tokyo" {
  # デフォルトのproviderを使用する
  cidr_block = "192.168.0.0/16"
}


# --- モジュールをmulti-regionで使う場合 ---

module "virginia" {
  source = "./vpc"

  # ここで明示的にproviderをセット！
  providers = {
    aws = aws.virginia
  }
}

module "tokyo" {
  # デフォルトのproviderを使用する
  source = "./vpc"
}

