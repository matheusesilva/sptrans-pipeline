# infra/s3.tf

resource "aws_s3_bucket" "data_lake" {
  bucket = "sptrans-data-lake-202603" # Mude para algo único
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
