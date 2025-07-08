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
  source      = "./security_group"
  name        = "module-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}
