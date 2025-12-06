
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


# tagで絞り込みもできる
data "aws_subnet" "public_staging" {
  tags = {
    Environment   = "Staging"
    Accessibility = "Public"
  }
}

# route53
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
