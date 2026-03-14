# ── Extrator: Lambda simples com zip ────────────────────────────────────────
# O zip é gerado pelo deploy.sh e referenciado aqui via S3 ou local path.
# Para o primeiro apply, um zip placeholder é aceito; o deploy.sh faz o update.

data "archive_file" "extractor_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/extractor/handler.py"
  output_path = "${path.module}/../build/extractor.zip"
}

resource "aws_lambda_function" "extractor" {
  function_name    = "sptrans-extractor"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.extractor_zip.output_path
  source_code_hash = data.archive_file.extractor_zip.output_base64sha256

  timeout     = 60
  memory_size = 256

  environment {
    variables = {
      SPTRANS_TOKEN = var.sptrans_token
      BRONZE_BUCKET = aws_s3_bucket.data_lake.bucket
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_logs]
}

resource "aws_cloudwatch_log_group" "extractor" {
  name              = "/aws/lambda/${aws_lambda_function.extractor.function_name}"
  retention_in_days = 7
}

# ── Transformer: Lambda com contêiner Docker (DuckDB + H3) ──────────────────
resource "aws_lambda_function" "transformer" {
  function_name = "sptrans-transformer"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.transformer.repository_url}:latest"

  ephemeral_storage {
    size = 2048
  }

  timeout     = 300
  memory_size = 1024

  environment {
    variables = {
      STATIC_BUCKET = aws_s3_bucket.static.bucket
    }
  }

  # Lifecycle: evita recriação a cada apply (a imagem é gerenciada pelo deploy.sh)
  lifecycle {
    ignore_changes = [image_uri]
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_logs]
}

resource "aws_cloudwatch_log_group" "transformer" {
  name              = "/aws/lambda/${aws_lambda_function.transformer.function_name}"
  retention_in_days = 7
}