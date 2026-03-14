# ── 1. Bucket privado – Bronze + Silver ─────────────────────────────────────
resource "aws_s3_bucket" "data_lake" {
  bucket = "sptrans-data-lake-${var.project_suffix}"
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "limpeza-bronze"
    status = "Enabled"
    filter { prefix = "bronze/" }
    expiration { days = 7 }
  }

  rule {
    id     = "transicao-silver-glacier"
    status = "Enabled"
    filter { prefix = "silver/" }
    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }
}

# ── 2. Bucket estático – Gold (Parquet público) + index.html ────────────────
resource "aws_s3_bucket" "static" {
  bucket = "sptrans-static-${var.project_suffix}"
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = false  # Allow restrictive bucket policy
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "static" {
  bucket = aws_s3_bucket.static.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

# ── Bucket Policy: CloudFront OAC + Referer validation ──────────────────────
resource "aws_s3_bucket_policy" "static_cloudfront_oac" {
  bucket = aws_s3_bucket.static.id
  depends_on = [
    aws_s3_bucket_public_access_block.static,
    aws_cloudfront_origin_access_control.static
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudFront OAC access
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.static.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.static.id}"
          }
        }
      }
    ]
  })
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Import OAC from cloudfront_waf.tf
resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "sptrans-static-oac"
  description                       = "OAC for SPTrans static bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CORS: necessário para o DuckDB WASM leer os Parquets no browser
resource "aws_s3_bucket_cors_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_website_configuration" "static" {
  bucket = aws_s3_bucket.static.id
  index_document { suffix = "index.html" }
}

# Lifecyle – limpa arquivos Gold com mais de 30 dias
resource "aws_s3_bucket_lifecycle_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    id     = "limpeza-gold"
    status = "Enabled"
    filter { prefix = "data/gold/" }
    expiration { days = 30 }
  }
}