resource "aws_ecr_repository" "transformer" {
  name                 = "sptrans-transformer"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "transformer" {
  repository = aws_ecr_repository.transformer.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Manter apenas as últimas 3 imagens"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}