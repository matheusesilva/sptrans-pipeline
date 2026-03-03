#!/bin/bash

# 1. Busca a URL do ECR via Terraform automaticamente
REPO_URL=$(terraform -chdir=infra output -raw repository_url)
REGION="us-east-1"

echo "Iniciando deploy para: $REPO_URL"

# 2. Login no ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REPO_URL

# 3. Build da imagem
docker build -t sptrans-pipeline .

# 4. Tag e Push
docker tag sptrans-pipeline:latest $REPO_URL:latest
docker push $REPO_URL:latest

echo "Imagem enviada com sucesso!"

# 5. Atualiza o Lambda para usar a nova imagem
echo "Atualizando o código do Lambda..."
aws lambda update-function-code \
    --function-name sptrans-extractor \
    --image-uri "$REPO_URL:latest"