output "certificate_arn" {
  value       = data.aws_acm_certificate.imported_certificate.arn
  description = "value of the acm certificate arn"
}