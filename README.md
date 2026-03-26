# 🚌 SPTrans Pipeline

Pipeline de dados serverless para coleta e processamento em tempo real das posições de ônibus da cidade de São Paulo, utilizando a API pública **SPTrans Olho Vivo**.

## 📋 Sumário

- [Visão Geral](#visão-geral)
- [Dashboard em Tempo Real](#dashboard-em-tempo-real)
- [Arquitetura](#arquitetura)
- [Estrutura do Projeto](#estrutura-do-projeto)
- [Tecnologias Utilizadas](#tecnologias-utilizadas)
- [Pré-requisitos](#pré-requisitos)
- [Configuração e Deploy](#configuração-e-deploy)
- [Infraestrutura (Terraform)](#infraestrutura-terraform)
- [Fluxo de Processamento Detalhado](#fluxo-de-processamento-detalhado)

---

## Visão Geral

Este projeto coleta automaticamente, a cada **5 minutos**, a posição em tempo real de toda a frota de ônibus de São Paulo via API SPTrans Olho Vivo. Os dados são armazenados em um **Data Lake serverless** no Amazon S3, seguindo a arquitetura **Medallion** (Bronze → Silver → Gold).

- **Bronze**: JSON bruto da API, preservado por **7 dias**
- **Silver**: Dados normalizados e particionados em formato **Delta Lake** com suporte a transações ACID, migra para Glacier após **90 dias**
- **Gold**: Camada analítica em formato **Parquet**, otimizada para consultas rápidas com DuckDB WASM

### Características principais:

✅ **Serverless 100%**: EventBridge → Step Functions → Lambda → S3 → CloudFront  
✅ **Totalmente automatizado**: Pipeline de 5 minutos sem necessidade de gerenciamento manual  
✅ **Data em tempo real**: Dashboard ao vivo com posição de ônibus atualizada continuamente  
✅ **Escalável**: Processa toda a frota de ~15.000 ônibus de SP sem gargalos  
✅ **Econômico**: Lifecycle policies reduzem custos de armazenamento automaticamente  
✅ **Observável**: CloudWatch Logs, Alarms e métricas de WAF integradas

---

## Dashboard em Tempo Real

**URL do Dashboard**: [https://d23nm32hbofn5.cloudfront.net/](https://d23nm32hbofn5.cloudfront.net/)
![Heatmap Screenshot](/docs/heatmap_screenshot.png)

### Características do Dashboard:

- **Mapa interativo em tempo real** com deck.gl (WebGL rendering performático)
- **DuckDB WASM** para consultas SQL diretas no navegador (sem backend necessário)
- **Visualização da frota SPTrans**: Densidade de ônibus por região de SP
- **Filtros por data e horário**: Explore dados históricos do Gold layer
- **Geolocalização**: Zoom e pan para explorar regiões específicas
- **Atualizações a cada 5 minutos**: Dados frescos conforme o pipeline processa

### Tecnologias do Frontend:

| Tecnologia  | Função                                            |
|-------------|---------------------------------------------------|
| **DuckDB WASM** | Engine SQL serverless no navegador                |
| **deck.gl** | Visualização WebGL de alta performance            |
| **Parquet** | Formato otimizado para consultas analíticas       |
| **CloudFront** | CDN global com cache inteligente                  |
| **S3** | Armazenamento do Gold layer (Parquet)            |

---

## Arquitetura

![AWS Archtecture](/docs/aws_achtecture.png)

### Fluxo de Dados Detalhado:

**1. Orquestração (a cada 5 minutos)**:
   - EventBridge dispara uma regra de agendamento
   - Inicia execução do Step Functions Express Workflow

**2. Extração (Lambda Extractor)**:
   - Autentica na API SPTrans Olho Vivo
   - Coleta posições em tempo real de toda a frota
   - Valida e normaliza JSON
   - Grava arquivo bruto na camada **Bronze** (S3)
   - Retorna metadados para o próximo stage

**3. Transformação (Lambda Transformer - Container)**:
   - Lê arquivo Bronze em JSON
   - Normaliza com Pandas (achata hierarquias)
   - Aplica transformações com DuckDB:
     - Validação de dados
     - Enriquecimento (H3 geohashing)
     - Particionamento por data
   - Escreve em formato **Delta Lake** na camada **Silver**
   - Gera agregações para camada **Gold** (Parquet)

**4. Disponibilização (Cloud Storage)**:
   - **Bronze**: JSON bruto (7 dias → deletado)
   - **Silver**: Delta Lake (90 dias → Glacier)
   - **Gold**: Parquet pronto para analytics (30 dias)

**5. Distribuição (CloudFront + WAF)**:
   - CloudFront serve dados com cache inteligente
   - WAF bloqueia abuso (>500 req/5min por IP)
   - Dashboard acessa via HTTPS com Origin Access Control

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

### Backend (Pipeline)

| Tecnologia         | Versão | Uso                                              |
|--------------------|--------|--------------------------------------------------|
| **Python**         | 3.12   | Linguagem principal                              |
| **AWS Lambda**     | -      | Execução serverless do pipeline                  |
| **AWS Step Functions** | -  | Orquestração e coordenação de estados            |
| **Amazon S3**      | -      | Data Lake (Bronze / Silver / Gold)               |
| **Amazon ECR**     | -      | Registro e versionamento de imagens Docker       |
| **Amazon EventBridge** | - | Agendamento de execução (trigger de 5 min)      |
| **AWS CloudWatch** | -      | Logs, métricas e alarmes                         |
| **AWS WAF**        | v2     | Rate limiting e proteção de bots                 |
| **CloudFront**     | -      | CDN global com cache inteligente                 |
| **Delta Lake**     | -      | Formato ACID transacional na camada Silver       |
| **DuckDB**         | 1.0+   | Engine SQL para transformações eficientes        |
| **Pandas**         | 2.0+   | Normalização e manipulação de dados              |
| **H3**             | -      | Geohashing para análises espaciais               |
| **Docker**         | -      | Containerização do Lambda Transformer            |
| **Terraform**      | 1.0+   | Infraestrutura como código (IaC)                 |

### Frontend (Dashboard)

| Tecnologia         | Uso                                              |
|--------------------|--------------------------------------------------|
| **DuckDB WASM**    | Engine SQL no navegador (sem backend)            |
| **deck.gl**        | Visualização WebGL performática de mapas         |
| **Parquet**        | Formato otimizado para consultas analíticas      |
| **HTML5 + CSS3**   | Interface responsiva                             |

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

| Recurso                          | Nome/Descrição                                         | Configuração |
|----------------------------------|--------------------------------------------------------|----------|
| **S3 - Data Lake**               | `sptrans-data-lake-{suffix}`                          | Privado, 3 camadas |
| **S3 - Static**                  | `sptrans-static-{suffix}`                             | Público (via CloudFront) |
| **S3 Lifecycle**                 | Bronze: 7 dias / Silver: 90d→Glacier / Gold: 30 dias | Automático |
| **ECR Repository**               | `sptrans-transformer`                                 | Keeps 3 images |
| **Lambda - Extractor**           | `sptrans-extractor`                                   | 256 MB, 60s timeout |
| **Lambda - Transformer**         | `sptrans-transformer`                                 | 1,024 MB, 300s, 2GB ephemeral |
| **Step Functions**               | `sptrans-pipeline`                                    | Express Workflow |
| **EventBridge**                  | `sptrans-pipeline-every-5-minutes`                    | rate(5 minutes) |
| **CloudFront**                   | Distribution com OAC                                  | HTTP/2 + HTTP/3 |
| **WAF (CloudFront)**             | `sptrans-cloudfront-waf`                              | Rate limit: 500/5min |
| **CloudWatch Logs**              | 3 log groups (Extractor, Transformer, Step Functions) | 7 dias retenção |
| **IAM Roles**                    | lambda_role, sfn_role, events_role                    | Least privilege |

---

## Fluxo de Processamento Detalhado

### 1. Extração (Lambda Extractor)

```python
# Input: Disparado pelo Step Functions a cada 5 minutos
# 1. Autentica na API SPTrans
# 2. Faz GET /Posicao (endpoint público)
# 3. Recebe JSON com ~15.000 ônibus
# 4. Valida estrutura e dados
# 5. Grava em Bronze
# Output: { bronze_key: "s3://...", bucket: "..." }
```

**Exemplo de arquivo Bronze**:
```
s3://sptrans-data-lake-202603/bronze/2026/03/26/frota_151523.json
```

### 2. Transformação (Lambda Transformer - Docker)

```python
# Input: Metadados do arquivo Bronze
# 1. Lê JSON de Bronze
# 2. Normaliza com Pandas (json_normalize)
#    - Achata array l[].vs[] (veículos por linha)
#    - Renomeia colunas (py→lat, px→lon, etc.)
# 3. Validação com DuckDB
#    - Verifica tipos
#    - Remove duplicatas
#    - Calcula H3 hexagons (geohashing)
# 4. Escreve Silver em Delta Lake (particionado por dia)
# 5. Gera agregações para Gold (Parquet)
# Output: { transform_result: {...}, gold_keys: [...] }
```

### 3. Estrutura de pastas no S3

```
s3://sptrans-data-lake-202603/
├── bronze/
│   ├── 2026/03/26/
│   │   ├── frota_151523.json          ← 7 dias, depois deletado
│   │   ├── frota_152023.json
│   │   └── frota_152523.json
│   └── ...
│
├── silver/
│   ├── posicao_onibus/
│   │   ├── data_processamento=2026-03-26/
│   │   │   ├── part-00000.parquet      ← Delta Lake (ACID)
│   │   │   └── part-00001.parquet
│   │   └── ...
│   └── _delta_log/
│       ├── 00000000000000000000.json   ← Transaction log
│       └── ...
│
s3://sptrans-static-202603/
├── data/gold/
│   ├── frota_2026_03_26.parquet        ← 30 dias, depois deletado
│   ├── frota_por_linha_2026_03_26.parquet
│   └── ...
└── index.html                          ← Dashboard
```

## Schema da camada Silver (Delta Lake)

| Coluna                   | Tipo        | Descrição                          |
|--------------------------|-------------|------------------------------------|
| `prefixo`                | `string`    | Prefixo do veículo (ex: "1001")    |
| `latitude`               | `float64`   | Latitude WGS84 da posição          |
| `longitude`              | `float64`   | Longitude WGS84 da posição         |
| `timestamp_transmissao`  | `int64`     | Unix timestamp do último ping      |
| `codigo_linha`           | `string`    | Código identificador da linha      |
| `destino_linha`          | `string`    | Letreiro/destino linha (ex: "Term. Vl. Mariana") |
| `h3_index`               | `string`    | H3 hexagon (geohashing, resolução 9) |
| `velocidade`             | `float64`   | Velocidade em km/h                 |
| `processado_em`          | `timestamp` | UTC timestamp do processamento     |
| `data_processamento`     | `string`    | Data partição (formato: YYYY-MM-DD) |

### Particionamento

- **Coluna de partição**: `data_processamento`
- **Formato**: Delta Lake (suporta ACID, time travel)
- **Retenção**: Movido para Glacier após 90 dias
- **Acesso**: Otimizado para queries por data

---

## Schema da camada Gold (Parquet)

### Tabela 1: `frota_agregada`

| Coluna              | Tipo    | Descrição                          |
|---------------------|---------|------------------------------------| 
| `data_processamento`| `date`  | Data da agregação                  |
| `codigo_linha`      | `string`| Linha de ônibus                    |
| `total_veiculos`    | `int32` | Total de veículos em operação      |
| `centroide_lat`     | `float` | Latitude média da linha            |
| `centroide_lon`     | `float` | Longitude média da linha           |
| `velocidade_media`  | `float` | Velocidade média (km/h)            |

### Tabela 2: `densidade_por_hexagon`

| Coluna              | Tipo    | Descrição                          |
|---------------------|---------|------------------------------------| 
| `data_processamento`| `date`  | Data da agregação                  |
| `h3_index`          | `string`| H3 hexagon (resolução 9)           |
| `latitude`          | `float` | Centro do hexagon (lat)            |
| `longitude`         | `float` | Centro do hexagon (lon)            |
| `densidade`         | `int32` | Quantidade de ônibus no hexagon    |
| `timestamp`         | `int64` | Último timestamp observado         |

**Retenção**: 30 dias, depois deletado automaticamente
