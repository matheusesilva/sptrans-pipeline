variable "sptrans_token" {
  description = "Token de autenticação da API SPTrans Olho Vivo"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_suffix" {
  description = "Sufixo único para nomear recursos globais (ex: bucket S3)"
  type        = string
  default     = "202603"
}