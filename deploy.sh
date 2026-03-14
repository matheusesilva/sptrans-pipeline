#!/usr/bin/env bash
# deploy.sh — SPTrans Pipeline
# Uso: ./deploy.sh [--skip-tf] [--skip-extractor] [--skip-transformer] [--skip-static]
#
# O que faz:
#   1. Terraform apply (provisiona / atualiza infra)
#   2. Build + push da imagem Docker do Transformer para o ECR
#   3. Atualiza o código do Lambda Transformer para a nova imagem
#   4. Injeta a URL do bucket no index.html e faz upload para o S3

set -euo pipefail

# ── Flags ────────────────────────────────────────────────────────────────────
SKIP_TF=false
SKIP_EXTRACTOR=false
SKIP_TRANSFORMER=false
SKIP_STATIC=false

for arg in "$@"; do
  case $arg in
    --skip-tf)          SKIP_TF=true ;;
    --skip-extractor)   SKIP_EXTRACTOR=true ;;
    --skip-transformer) SKIP_TRANSFORMER=true ;;
    --skip-static)      SKIP_STATIC=true ;;
  esac
done

# ── Configuração ─────────────────────────────────────────────────────────────
REGION="us-east-1"
INFRA_DIR="infra"
SRC_DIR="src"
BUILD_DIR="build"

mkdir -p "$BUILD_DIR"

# ── Cores para log ───────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[deploy]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $*"; }
err()  { echo -e "${RED}[erro]${NC}  $*"; exit 1; }

# ── 1. Terraform init (prepare infra) ────────────────────────────────────────
if [ "$SKIP_TF" = false ]; then
  log "Inicializando Terraform…"
  terraform -chdir="$INFRA_DIR" init -upgrade -input=false
fi

# ── 2. Build and push Transformer Docker image BEFORE terraform apply ────────
# This ensures the ECR image exists before Lambda tries to reference it
if [ "$SKIP_TF" = false ] || [ "$SKIP_TRANSFORMER" = false ]; then
  log "Lendo outputs do Terraform para ECR repo…"
  TRANSFORMER_REPO=$(terraform -chdir="$INFRA_DIR" output -raw transformer_repo_url 2>/dev/null || echo "")
  
  if [ -z "$TRANSFORMER_REPO" ]; then
    log "ECR repo não está pronto ainda, pulando build do Transformer por enquanto…"
  elif [ "$SKIP_TRANSFORMER" = false ]; then
    log "Login no ECR…"
    aws ecr get-login-password --region "$REGION" \
      | docker login --username AWS --password-stdin "$TRANSFORMER_REPO"

    log "Build da imagem Docker do Transformer…"
    docker build \
      --platform linux/amd64 \
      -t sptrans-transformer:latest \
      "$SRC_DIR/transformer"

    log "Push para o ECR…"
    docker tag sptrans-transformer:latest "$TRANSFORMER_REPO:latest"
    docker push "$TRANSFORMER_REPO:latest"
    log "Docker image pushado com sucesso."
  fi
fi

# ── 3. Terraform apply (now image exists in ECR) ──────────────────────────────
if [ "$SKIP_TF" = false ]; then
  log "Executando terraform apply…"
  terraform -chdir="$INFRA_DIR" apply -auto-approve -input=false
  log "Terraform concluído."
fi

# ── Lê outputs do Terraform ──────────────────────────────────────────────────
log "Lendo outputs do Terraform…"
TRANSFORMER_REPO=$(terraform -chdir="$INFRA_DIR" output -raw transformer_repo_url)
STATIC_BUCKET=$(terraform   -chdir="$INFRA_DIR" output -raw static_bucket)
STATIC_BASE_URL=$(terraform  -chdir="$INFRA_DIR" output -raw static_bucket_base_url)

log "  Transformer ECR : $TRANSFORMER_REPO"
log "  Static bucket   : $STATIC_BUCKET"
log "  Static base URL : $STATIC_BASE_URL"

# ── 4. Extrator — o Terraform já empacota o zip via archive_file ─────────────
# Nada adicional a fazer aqui; o terraform apply já atualizou a função.
if [ "$SKIP_EXTRACTOR" = false ]; then
  log "Extrator atualizado pelo Terraform (zip gerado em build/)."
fi

# ── 5. Transformer — update Lambda if needed ─────────────────────────────────
if [ "$SKIP_TRANSFORMER" = false ]; then
  log "Atualizando Lambda Transformer para a nova imagem…"
  aws lambda update-function-code \
    --region "$REGION" \
    --function-name "sptrans-transformer" \
    --image-uri "$TRANSFORMER_REPO:latest" \
    --output text \
    --query "CodeSha256"

  # Aguarda a atualização concluir
  log "Aguardando Lambda Transformer ficar ativo…"
  aws lambda wait function-updated-v2 \
    --region "$REGION" \
    --function-name "sptrans-transformer"

  log "Lambda Transformer atualizado com sucesso."
fi

# ── 6. Site estático — injeta URL e faz upload ───────────────────────────────
if [ "$SKIP_STATIC" = false ]; then
  log "Gerando index.html com URL do bucket…"
  sed "s|%%STATIC_BUCKET_URL%%|${STATIC_BASE_URL}|g" \
    "$SRC_DIR/static/index.html" > "$BUILD_DIR/index.html"

  log "Upload do index.html para s3://${STATIC_BUCKET}/static/index.html…"
  aws s3 cp "$BUILD_DIR/index.html" \
    "s3://${STATIC_BUCKET}/static/index.html" \
    --content-type "text/html; charset=utf-8" \
    --cache-control "no-cache"

  WEBSITE_URL="http://${STATIC_BUCKET}.s3-website-${REGION}.amazonaws.com/static/index.html"
  log "✅ Site disponível em: ${WEBSITE_URL}"
fi

log ""
log "════════════════════════════════════════════════"
log "  Deploy concluído!"
log "  Site  → ${STATIC_BASE_URL}/static/index.html"
log "  Dados → ${STATIC_BASE_URL}/data/gold/YYYY-MM-DD/heatmap_HHMM.parquet"
log "════════════════════════════════════════════════"
