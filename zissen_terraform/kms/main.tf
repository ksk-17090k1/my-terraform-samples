resource "aws_kms_key" "example" {
  description = "Example Customer Master Key"
  # ローテーション。基本trueでOK
  enable_key_rotation = true
  # 鍵の有効化
  # 一度作った鍵は削除しないのがベスプラなので、不要になったら削除ではなくここをfalseにする
  is_enabled = true
  # 削除までの猶予期間
  deletion_window_in_days = 30
}

# カスタマーマスターキーにはUUIDが割り当てられるが、人間にはわかりにくいのエイリアスで分かりやすくする
resource "aws_kms_alias" "example" {
  # nameには"alias/"というprefixが必須！！"
  name          = "alias/example"
  target_key_id = aws_kms_key.example.key_id
}
