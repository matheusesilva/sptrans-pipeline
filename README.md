# 🚌 SPTrans Pipeline

Pipeline de dados serverless para coleta e processamento em tempo real das posições de ônibus da cidade de São Paulo, utilizando a API pública **SPTrans Olho Vivo**.

## 📋 Sumário

- [Visão Geral](#visão-geral)
- [Arquitetura](#arquitetura)
- [Estrutura do Projeto](#estrutura-do-projeto)
- [Tecnologias Utilizadas](#tecnologias-utilizadas)
- [Pré-requisitos](#pré-requisitos)
- [Configuração e Deploy](#configuração-e-deploy)
- [Infraestrutura (Terraform)](#infraestrutura-terraform)
- [Pipeline de Dados](#pipeline-de-dados)
- [Testes Locais](#testes-locais)

---

## Visão Geral

Este projeto coleta automaticamente, a cada **5 minutos**, a posição em tempo real de toda a frota de ônibus de São Paulo via API SPTrans Olho Vivo. Os dados são armazenados em um Data Lake no Amazon S3, seguindo a arquitetura **Medallion** (Bronze → Silver → Gold).

- **Bronze**: JSON bruto da API, preservado por 30 dias.
- **Silver**: Dados normalizados e particionados em formato **Delta Lake**, com transição para Glacier após 90 dias.
- **Gold**: Camada analítica (pronta para consumo por ferramentas de BI).

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                            │
│                                                             │
│  ┌──────────────┐       ┌──────────────┐                    │
│  │  EventBridge │─────▶│   Lambda     │                    │
│  │  (5 min)     │       │  (Container) │                    │
│  └──────────────┘       └──────┬───────┘                    │
│                                │                            │
│                                ▼                            │
│                     ┌──────────────────┐                    │
│                     │   Amazon S3      │                    │
│                     │  (Data Lake)     │                    │
│                     │                  │                    │
│                     │  bronze/         │ ← JSON bruto       │
│                     │  silver/         │ ← Delta Lake       │
│                     │  gold/           │ ← Analítico        │
│                     └──────────────────┘                    │
│                                                             │
│  ┌──────────────┐                                           │
│  │  Amazon ECR  │ ← Imagem Docker do Lambda                 │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
         ▲
         │  HTTP (a cada 5 min)
         │
┌────────────────────┐
│  SPTrans Olho Vivo │
│  API v2.1          │
└────────────────────┘
```

---

## Estrutura do Projeto

```
sptrans-pipeline/
├── src/
│   └── lambda_handler.py     # Lógica principal do Lambda (extração + transformação)
├── infra/
│   ├── provider.tf           # Configuração do provider AWS
│   ├── variables.tf          # Variáveis (token SPTrans)
│   ├── ecr.tf                # Repositório ECR para a imagem Docker
│   ├── lambda.tf             # Função Lambda + IAM Role e Policies
│   ├── events.tf             # EventBridge (agendamento a cada 5 min)
│   ├── s3.tf                 # Bucket S3 com camadas e lifecycle policies
│   └── outputs.tf            # Outputs do Terraform
├── Dockerfile                # Imagem baseada no Lambda Python 3.12 (ECR público)
├── deploy.sh                 # Script de build, push e atualização do Lambda
├── requirements.txt          # Dependências Python
└── README.md
```

---

## Tecnologias Utilizadas

| Tecnologia         | Uso                                              |
|--------------------|--------------------------------------------------|
| **Python 3.12**    | Linguagem principal                              |
| **AWS Lambda**     | Execução serverless do pipeline                  |
| **Amazon S3**      | Data Lake (Bronze / Silver / Gold)               |
| **Amazon ECR**     | Registro da imagem Docker                        |
| **EventBridge**    | Agendamento da execução a cada 5 minutos         |
| **Delta Lake**     | Formato da camada Silver (ACID, particionado)    |
| **Pandas**         | Normalização e transformação dos dados           |
| **Docker**         | Empacotamento do Lambda como imagem de container |
| **Terraform**      | Infraestrutura como código (IaC)                 |

---

## Pré-requisitos

- [AWS CLI](https://aws.amazon.com/cli/) configurado com credenciais válidas
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [Docker](https://www.docker.com/) instalado e em execução
- Token de autenticação da [API SPTrans Olho Vivo](https://www.sptrans.com.br/desenvolvedores/)
- Python 3.12+ (para testes locais)

---

## Configuração e Deploy

### 1. Clone o repositório

```bash
git clone <url-do-repositorio>
cd sptrans-pipeline
```

### 2. Provisione a infraestrutura com Terraform

```bash
cd infra
terraform init
terraform apply -var="sptrans_token=SEU_TOKEN_AQUI"
```

> O Terraform criará o bucket S3, o repositório ECR, a função Lambda e a regra do EventBridge.

### 3. Faça o build e o deploy da imagem

Na raiz do projeto, execute o script de deploy:

```bash
chmod +x deploy.sh
./deploy.sh
```

O script realiza automaticamente:
1. Obtém a URL do ECR via `terraform output`
2. Autentica o Docker no ECR
3. Faz o build da imagem Docker
4. Envia a imagem para o ECR
5. Atualiza o código da função Lambda

---

## Infraestrutura (Terraform)

### Recursos provisionados

| Recurso                          | Descrição                                              |
|----------------------------------|--------------------------------------------------------|
| `aws_s3_bucket`                  | Bucket `sptrans-data-lake-202603` (acesso público bloqueado) |
| `aws_s3_bucket_lifecycle_configuration` | Bronze expira em 30 dias; Silver migra para Glacier em 90 dias |
| `aws_ecr_repository`             | Repositório Docker para a imagem do Lambda            |
| `aws_lambda_function`            | `sptrans-extractor` — 1024 MB, timeout de 300s        |
| `aws_iam_role` / `aws_iam_policy`| Role com permissões de S3 (PutObject, GetObject, ListBucket) e CloudWatch Logs |
| `aws_cloudwatch_event_rule`      | Agendamento `rate(5 minutes)`                         |

### Variáveis

| Variável         | Descrição                                  | Obrigatória |
|------------------|--------------------------------------------|:-----------:|
| `sptrans_token`  | Token de autenticação da API Olho Vivo     | ✅           |

---

## Pipeline de Dados

### Fluxo de execução do Lambda

```
1. Autenticação na API SPTrans Olho Vivo
         │
         ▼
2. GET /Posicao  →  JSON bruto com todas as linhas e veículos
         │
         ├──▶ Bronze: s3://bucket/bronze/YYYY/MM/DD/frota_HHMMSS.json
         │
         ▼
3. Normalização com Pandas (json_normalize)
   - Achata o array `l[].vs[]` (veículos por linha)
   - Renomeia colunas (py→latitude, px→longitude, etc.)
   - Adiciona colunas de controle (processado_em, data_processamento)
         │
         ▼
4. Silver: s3://bucket/silver/posicao_onibus/
   - Formato Delta Lake, particionado por data_processamento
   - Modo: append
```

### Schema da camada Silver

| Coluna                   | Tipo        | Descrição                          |
|--------------------------|-------------|------------------------------------|
| `prefixo`                | `string`    | Prefixo do veículo                 |
| `latitude`               | `float`     | Latitude da posição                |
| `longitude`              | `float`     | Longitude da posição               |
| `timestamp_transmissao`  | `string`    | Último timestamp de transmissão    |
| `codigo_linha`           | `string`    | Código identificador da linha      |
| `destino_linha`          | `string`    | Letreiro/destino da linha          |
| `processado_em`          | `timestamp` | Momento do processamento           |
| `data_processamento`     | `string`    | Data (chave de partição)           |

---

## Testes Locais

### Instalar dependências

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Executar os testes

```bash
# Teste de extração e gravação na Bronze
python test/extract_to_bronze.py

# Teste de transformação para a Silver
python test/transform_to_silver.py

# Teste de leitura dos dados
python test/read_test.py
```

> ⚠️ Os testes de integração exigem credenciais AWS configuradas e acesso à API SPTrans Olho Vivo.
