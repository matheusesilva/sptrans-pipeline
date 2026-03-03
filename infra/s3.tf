# infra/s3.tf

resource "aws_s3_bucket" "data_lake" {
  bucket = "sptrans-data-lake-202603"
}

# Bloquear acesso público
resource "aws_s3_bucket_public_access_block" "data_lake_json" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Organizando as pastas (Bronze, Silver, Gold) via "objetos" vazios
resource "aws_s3_object" "folders" {
  for_each = toset(["bronze/", "silver/", "gold/"])
  bucket   = aws_s3_bucket.data_lake.id
  key      = each.value
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake_lifecycle" {
  bucket = aws_s3_bucket.data_lake.id

  # Regra para a Camada BRONZE
  rule {
    id     = "limpeza-bronze"
    status = "Enabled"

    filter {
      prefix = "bronze/" # Aplica apenas aos arquivos da pasta bronze
    }

    expiration {
      days = 30 # Apaga automaticamente após 30 dias
    }
  }

  rule {
    id     = "transicao-silver-glacier"
    status = "Enabled"

    filter {
      prefix = "silver/"
    }

    # Move para Glacier Instant Retrieval após 90 dias
    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }
}