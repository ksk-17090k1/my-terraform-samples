provider "aws" {
  region = "ap-northeast-1"
}


resource "aws_instance" "example" {
  ami = "ami-0c3fd0f5d33134a76"
  # data sourceの参照
  #   ami = data.aws_ami.recent_amazon_linux.image_id

  # variableの参照
  instance_type = var.example_instance_type
  # local variableの参照
  #   instance_type = local.example_instance_type

  tags = {
    Name = "example"
  }
}

# --- variable ---
# NOTE: TF_VAR_example_instance_type という環境変数を作るとterraformが勝手に上書きする
# コマンドライン引数的に上書きもできる
variable "example_instance_type" {
  default = "t3.micro"
}

# --- local variable ---
locals {
  example_instance_type = "t3.micro"
}

# --- data source ---
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

# --- module ---
module "web_server" {
  source = "./http_server"
  # moduleの中のvariableを上書きする
  instance_type = "t3.micro"
}


# --- output ---
output "example_instance_id" {
  value = aws_instance.example.id
}

output "public_dns" {
  value = module.web_server.public_dns

}
