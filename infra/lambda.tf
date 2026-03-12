# 1. Lambda Role
resource "aws_iam_role" "lambda_role" {
  name = "sptrans_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 2. Permissão para o Lambda escrever Logs e acessar o S3
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_s3_policy" {
  name = "sptrans_lambda_s3_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = [
        aws_s3_bucket.data_lake.arn,
        "${aws_s3_bucket.data_lake.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

# 3. Função Lambda
resource "aws_lambda_function" "sptrans_pipeline" {
  function_name = "sptrans-extractor"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.pipeline_repo.repository_url}:latest"

  timeout     = 300
  memory_size = 1024

  environment {
    variables = {
      SPTRANS_TOKEN = var.sptrans_token
      BUCKET_NAME   = aws_s3_bucket.data_lake.bucket
    }
  }
}