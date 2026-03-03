# infra/ecr.tf

resource "aws_ecr_repository" "pipeline_repo" {
  name                 = "sptrans-pipeline"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Política para manter apenas as últimas 5 imagens
resource "aws_ecr_lifecycle_policy" "repo_policy" {
  repository = aws_ecr_repository.pipeline_repo.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Manter apenas as últimas 3 imagens",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": 3
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}