## Variables for Model Evaluation Batch

variable "aws_region" {
  type        = string
  description = "AWSリージョン"
}

variable "aws_account_id" {
  type        = string
  description = "AWSアカウントID"
}

variable "system_name" {
  type        = string
  description = "アプリケーションのシステム名"
}

variable "environment" {
  type        = string
  description = "環境名（dev, stg, prd）"
}

variable "vpc_id" {
  type        = string
  description = "VPCのID"
}

variable "subnet_private_01_id" {
  type        = string
  description = "プライベートサブネット01のID"
}

variable "subnet_private_02_id" {
  type        = string
  description = "プライベートサブネット02のID"
}

# AWS Batch Variables
variable "batch_job_vcpu" {
  type        = number
  description = "Batch JobのvCPU数"
  default     = 2
}

variable "batch_job_memory" {
  type        = number
  description = "Batch Jobのメモリ（MB）"
  default     = 4096
}

variable "batch_job_timeout" {
  type        = number
  description = "Batch Jobのタイムアウト（秒）"
  default     = 3600
}

variable "evaluation_batch_schedule_expression" {
  type        = string
  description = "パイプラインのスケジュール式（cron）"
  default     = "cron(0 5 * * ? *)"
}

variable "evaluation_batch_schedule_status" {
  type        = bool
  description = "パイプラインスケジュールのステータス（有効/無効）"
  default     = false
}
