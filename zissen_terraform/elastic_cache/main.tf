resource "aws_elasticache_parameter_group" "example" {
  name   = "example"
  family = "redis5.0"

  # クラスターモードを無効にする設定
  parameter {
    name  = "cluster-enabled"
    value = "no"
  }
}

resource "aws_elasticache_subnet_group" "example" {
  name = "example"
  # 異なるAZのsubnetを指定する必要がある
  subnet_ids = [aws_subnet.private_0.id, aws_subnet.private_1.id]
}

resource "aws_elasticache_replication_group" "example" {
  replication_group_id = "example"
  description          = "Cluster Disabled"
  # redis / memcached
  engine         = "redis"
  engine_version = "5.0.4"
  # node数 (プライマリ+レプリカの合計数)
  num_cache_clusters = 3
  node_type          = "cache.m3.medium"
  # スナップショット取得タイミング(1hが一般的)
  snapshot_window = "09:10-10:10"
  # スナップショットの保持日数
  snapshot_retention_limit = 7
  # メンテナンスを入れてよいタイミング(1hが一般的)
  # メンテの種類はAWSが自動実行するものと、実装者の設定変更によるものがある。
  maintenance_window = "mon:10:40-mon:11:40"
  port               = 6379
  # 設定変更を即時かメンテナンスウィンドウで行うか
  apply_immediately    = false
  security_group_ids   = [module.redis_sg.security_group_id]
  parameter_group_name = aws_elasticache_parameter_group.example.name
  subnet_group_name    = aws_elasticache_subnet_group.example.name

  # マルチAZにするか (num_cache_clustersが2以上のときのみ有効)
  multi_az_enabled = true
  # 自動フェイルオーバーを有効にする (multi_az_enabledがtrueのときは強制的にtrue)
  automatic_failover_enabled  = true
  preferred_cache_cluster_azs = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.cloudwatch_log_group.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.log_group.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }
}

resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/elasticache/ltd-tob-recommend-logs"
  retention_in_days = 14
}

module "redis_sg" {
  source      = "../network/security_group"
  name        = "redis-sg"
  vpc_id      = aws_vpc.example.id
  port        = 6379
  cidr_blocks = [aws_vpc.example.cidr_block]
}
