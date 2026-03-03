# infra/outputs.tf

output "repository_url" {
  description = "A URL do repositório ECR para fazer o push da imagem"
  value       = aws_ecr_repository.pipeline_repo.repository_url
}

output "bucket_name" {
  description = "O nome do bucket criado"
  value       = aws_s3_bucket.data_lake.bucket
}