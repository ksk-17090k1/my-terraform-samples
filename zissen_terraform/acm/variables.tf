variable "environment" {
  description = "The environment in which the Lambda function is running"
  type        = string
  default     = "dev"
}

variable "common_name" {
  description = "The name of Certificate common name"
  type        = string
  default     = "example.com"
}

variable "certificate_bucket_name" {
  description = "The name of the S3 bucket"
  type        = string
  default     = "certificate-bucket"
}
