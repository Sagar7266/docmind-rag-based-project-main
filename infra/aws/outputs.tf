output "aws_region" {
  value = var.aws_region
}

output "frontend_bucket" {
  value = aws_s3_bucket.frontend.bucket
}

output "backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "instance_id" {
  value = aws_instance.backend.id
}

output "app_url" {
  value = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "api_public_ip" {
  value = aws_eip.backend.public_ip
}
