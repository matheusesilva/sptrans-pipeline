import pandas as pd
import requests
import boto3
import os
import json
from datetime import datetime
from deltalake.writer import write_deltalake

def handler(event, context):
    token = os.environ['SPTRANS_TOKEN']
    bucket = os.environ['BUCKET_NAME']
    
    session = requests.Session()

    headers = {
        "User-Agent": "curl/7.81.0",
        "Content-Length": "0"
    }

    auth_url = f"http://api.olhovivo.sptrans.com.br/v2.1/Login/Autenticar?token={token}"

    resp = session.post(auth_url, headers=headers, data="")

    print(resp.status_code, resp.text)

    if resp.status_code != 200 or resp.text.strip() != "true":
        raise Exception(f"Falha na auth: {resp.status_code} - {resp.text}")

    dados = session.get(
        "http://api.olhovivo.sptrans.com.br/v2.1/Posicao"
    ).json()
    
    # --- NOVO: SALVAR NA BRONZE (JSON BRUTO) ---
    s3_client = boto3.client('s3')
    now = datetime.now()
    # Caminho organizado: bronze/ano/mes/dia/frota_hora_minuto.json
    bronze_key = f"bronze/{now.strftime('%Y/%m/%d/frota_%H%M%S')}.json"
    
    s3_client.put_object(
        Bucket=bucket,
        Key=bronze_key,
        Body=json.dumps(dados),
        ContentType='application/json'
    )
    print(f"Arquivo salvo na Bronze: {bronze_key}")
    # ------------------------------------------

    # 3. Transformação para Silver
    df = pd.json_normalize(
        dados['l'], 
        record_path=['vs'], 
        meta=['c', 'cl', 'lt0', 'lt1'], 
        record_prefix='veiculo_'
    )
    
    # Limpeza (seus ajustes que funcionaram)
    df = df.rename(columns={
        'veiculo_p': 'prefixo',
        'veiculo_py': 'latitude',
        'veiculo_px': 'longitude',
        'veiculo_ta': 'timestamp_transmissao',
        'c': 'codigo_linha',
        'lt0': 'destino_linha'
    })

    df['prefixo'] = df['prefixo'].astype(str)
    df['latitude'] = pd.to_numeric(df['latitude'], errors='coerce').astype(float)
    df['longitude'] = pd.to_numeric(df['longitude'], errors='coerce').astype(float)
    df['codigo_linha'] = df['codigo_linha'].astype(str)
    df['processado_em'] = pd.Timestamp.now()
    df['data_processamento'] = pd.Timestamp.now().strftime('%Y-%m-%d')

    df = df.dropna(axis=1, how='all')
    
    # 4. Escrita no Delta Lake (Silver)
    silver_path = f"s3://{bucket}/silver/posicao_onibus/"
    write_deltalake(silver_path, df, mode="append", partition_by=["data_processamento"])
    
    return {
        "status": "sucesso", 
        "linhas_processadas": len(df),
        "bronze_path": bronze_key
    }