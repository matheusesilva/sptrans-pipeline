output "transformer_repo_url" {
  description = "URL do repositório ECR do Transformer"
  value       = aws_ecr_repository.transformer.repository_url
}

output "data_lake_bucket" {
  description = "Bucket privado (Bronze + Silver)"
  value       = aws_s3_bucket.data_lake.bucket
}

output "static_bucket" {
  description = "Bucket público (Gold + site estático)"
  value       = aws_s3_bucket.static.bucket
}

output "static_website_url" {
  description = "URL do site estático"
  value       = "http://${aws_s3_bucket.static.bucket}.s3-website-${var.aws_region}.amazonaws.com"
}

output "static_bucket_base_url" {
  description = "URL base do bucket estático (para o DuckDB WASM)"
  value       = "https://${aws_cloudfront_distribution.static.domain_name}"
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.static.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.static.id
}

output "sfn_state_machine_arn" {
  description = "ARN do State Machine do Step Functions"
  value       = aws_sfn_state_machine.pipeline.arn
}