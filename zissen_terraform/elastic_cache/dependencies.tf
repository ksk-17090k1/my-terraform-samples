resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
  # AWSのDNSサーバによる名前解決を有効に
  enable_dns_support = true
  # VPC内のリソースにパブリックDNSホスト名を自動的に割り当てる
  enable_dns_hostnames = true

  tags = {
    Name = "example"
  }
}

# --- public subnet ---
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.0.0/24"
  # このサブネットで起動したインスタンスにpublic IPを自動で割り当てる
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id
}

# route: route tableの1 recordに相当
# この設定はVPC以外の通信をインターネットに流すためのもの
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.example.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


# --- private subnet ---
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.64.0/24"
  availability_zone = "ap-northeast-1a"
  # privateなので
  map_public_ip_on_launch = false
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# --- NAT Gateway ---

# EIPやNAT Gatewayは暗黙的にInternet Gatewayに依存している。
# そのため、Internet Gatewayの作成後にNAT Gatewayを作成する必要がある。
# よって、depends_onにInternet Gatewayを指定する

# Elastic IP
resource "aws_eip" "nat_gateway" {
  # VPC内でEIPを作成する
  domain     = "vpc"
  depends_on = [aws_internet_gateway.example]
}

resource "aws_nat_gateway" "example" {
  # NAT GatewayにElastic IPを割り当てる
  allocation_id = aws_eip.nat_gateway.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.example]
}

resource "aws_route" "private" {
  route_table_id         = aws_route_table.private.id
  nat_gateway_id         = aws_nat_gateway.example.id
  destination_cidr_block = "0.0.0.0/0"
}

# -- security group ---
# モジュールをつかう
module "example_sg" {
  source      = "../network/security_group"
  name        = "module-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}


# --- public subnet (Multi-AZ) ---
resource "aws_subnet" "public_0" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
}

# route tableの作成は省略。route tableにはInternet Gatewayが紐づいている
resource "aws_route_table_association" "public_0" {
  subnet_id      = aws_subnet.public_0.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# --- private subnet (Multi-AZ) ---

resource "aws_subnet" "private_0" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.65.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.66.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = false
}

# NOTE: 依存するInternet GatewayはMulti-AZの場合でも単一！
# ただし、EIPとNat GatewayはAZごとに作成する必要がある！（実は１つでもいけるが冗長性のため）

resource "aws_eip" "nat_gateway_0" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.example]
}

resource "aws_eip" "nat_gateway_1" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.example]
}

resource "aws_nat_gateway" "nat_gateway_0" {
  allocation_id = aws_eip.nat_gateway_0.id
  subnet_id     = aws_subnet.public_0.id
  depends_on    = [aws_internet_gateway.example]
}

resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_gateway_1.id
  subnet_id     = aws_subnet.public_1.id
  depends_on    = [aws_internet_gateway.example]
}
resource "aws_route_table" "private_0" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route" "private_0" {
  route_table_id         = aws_route_table.private_0.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_0.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route" "private_1" {
  route_table_id         = aws_route_table.private_1.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_1.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private_0" {
  subnet_id      = aws_subnet.private_0.id
  route_table_id = aws_route_table.private_0.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1.id
}
