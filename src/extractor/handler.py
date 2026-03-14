"""
Lambda Extrator - Camada Bronze
Responsabilidade: Autenticar na API SPTrans, buscar posições dos ônibus
e salvar o JSON bruto na camada bronze do S3.
"""
import boto3
import os
import json
import http.cookiejar
import urllib.request
from datetime import datetime, timezone


def handler(event, context):
    token = os.environ["SPTRANS_TOKEN"]
    bucket = os.environ["BRONZE_BUCKET"]

    cookie_jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cookie_jar)
    )

    # 1. Autenticação
    auth_url = f"http://api.olhovivo.sptrans.com.br/v2.1/Login/Autenticar?token={token}"
    auth_req = urllib.request.Request(auth_url, data=b"", method="POST")
    auth_req.add_header("User-Agent", "curl/7.81.0")
    auth_req.add_header("Content-Length", "0")

    with opener.open(auth_req) as resp:
        auth_text = resp.read().decode()

    if auth_text.strip() != "true":
        raise Exception(f"Falha na autenticação SPTrans: {auth_text}")

    # 2. Busca posições
    pos_req = urllib.request.Request(
        "http://api.olhovivo.sptrans.com.br/v2.1/Posicao",
        headers={"User-Agent": "curl/7.81.0"},
    )
    with opener.open(pos_req) as resp:
        dados = json.loads(resp.read().decode())

    # 3. Salva JSON bruto na camada Bronze
    now = datetime.now(timezone.utc)
    bronze_key = f"bronze/{now.strftime('%Y/%m/%d/frota_%H%M%S')}.json"

    boto3.client("s3").put_object(
        Bucket=bucket,
        Key=bronze_key,
        Body=json.dumps(dados),
        ContentType="application/json",
    )

    print(f"[Extrator] Bronze salvo: s3://{bucket}/{bronze_key}")

    # Retorna o caminho para o Step Functions passar ao Transformer
    return {
        "bronze_key": bronze_key,
        "bucket": bucket,
    }