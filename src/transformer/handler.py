"""
Lambda Transformer - Camadas Silver e Gold
Responsabilidade:
  - Ler o JSON bruto da Bronze
  - Transformar com DuckDB (sem pandas)
  - Adicionar coordenadas H3 nas resoluções 6, 7, 8 e 9
  - Adicionar timestamp normalizado de 5 em 5 minutos
  - Escrever Silver (dados por veículo) no bucket privado
  - Escrever Gold no bucket estático:
      · heatmap_{hhmm}.parquet   — agregado por H3 (densidade por hexágono)
      · positions_{hhmm}.parquet — posições brutas por veículo (para ScatterplotLayer)
      · manifest.json            — índice dos snapshots disponíveis no dia
"""
import boto3
import duckdb
import h3
import json
import os
from datetime import datetime, timezone

TMP_RAW       = "/tmp/raw.json"
TMP_SILVER    = "/tmp/silver.parquet"
TMP_HEATMAP   = "/tmp/heatmap.parquet"
TMP_POSITIONS = "/tmp/positions.parquet"
TMP_MANIFEST  = "/tmp/manifest.json"


# ─── Helpers ──────────────────────────────────────────────────────────────────

def normalize_5min(dt: datetime) -> datetime:
    """Trunca o datetime para o intervalo de 5 minutos mais próximo (floor)."""
    return dt.replace(minute=(dt.minute // 5) * 5, second=0, microsecond=0)


def safe_h3(lat: float, lon: float, res: int) -> str | None:
    try:
        return h3.latlng_to_cell(lat, lon, res)
    except Exception:
        return None


def flatten_dados(dados: dict, ts_5min: datetime) -> list[dict]:
    """
    Transforma a estrutura aninhada da API SPTrans em lista de registros planos.
    Cada registro representa um veículo individual com coordenadas H3 pré-calculadas.
    """
    ts_str   = ts_5min.isoformat()
    date_str = ts_5min.strftime("%Y-%m-%d")
    hora_str = ts_5min.strftime("%H:%M")

    rows = []
    for linha in dados.get("l", []):
        for veiculo in linha.get("vs", []):
            try:
                lat = float(veiculo.get("py") or 0)
                lon = float(veiculo.get("px") or 0)
            except (TypeError, ValueError):
                continue

            if not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
                continue

            # Coordenadas fora do município de SP — descarta ruído
            if not (-24.1 <= lat <= -23.3) or not (-47.0 <= lon <= -46.1):
                continue

            rows.append({
                "codigo_linha":          str(linha.get("c",   "")),
                "codigo_linha_interno":  str(linha.get("cl",  "")),
                "destino_linha":         str(linha.get("lt0", "")),
                "origem_linha":          str(linha.get("lt1", "")),
                "prefixo":               str(veiculo.get("p", "")),
                "latitude":              lat,
                "longitude":             lon,
                "timestamp_transmissao": str(veiculo.get("ta", "")),
                "acessivel":             bool(veiculo.get("a", False)),
                # H3 em 4 resoluções: r6=macro, r7=bairro, r8=quadra, r9=rua
                "h3_r6": safe_h3(lat, lon, 6),
                "h3_r7": safe_h3(lat, lon, 7),
                "h3_r8": safe_h3(lat, lon, 8),
                "h3_r9": safe_h3(lat, lon, 9),
                "timestamp_5min":        ts_str,
                "data_processamento":    date_str,
                "hora_5min":             hora_str,
            })
    return rows


def update_manifest(s3, static_bucket: str, date_str: str, hhmm: str) -> None:
    """
    Mantém um manifest.json por dia no bucket estático listando todos os
    snapshots disponíveis. O frontend usa isso para descobrir o slot mais
    recente sem fazer HEAD requests individuais (que a S3 bloqueia sem auth).

    Formato:
    {
      "date": "2026-03-13",
      "updated_at": "2026-03-13T17:45:00+00:00",
      "snapshots": ["0000", "0005", ..., "1745"]   ← ordenados
    }
    """
    manifest_key = f"data/gold/{date_str}/manifest.json"

    # Tenta ler o manifest existente do dia
    existing_snapshots: list[str] = []
    try:
        obj = s3.get_object(Bucket=static_bucket, Key=manifest_key)
        existing = json.loads(obj["Body"].read())
        existing_snapshots = existing.get("snapshots", [])
    except s3.exceptions.NoSuchKey:
        pass
    except Exception as exc:
        print(f"[Transformer] Aviso ao ler manifest: {exc}")

    # Adiciona o snapshot atual (sem duplicatas, mantém ordenado)
    if hhmm not in existing_snapshots:
        existing_snapshots.append(hhmm)
        existing_snapshots.sort()

    manifest = {
        "date":       date_str,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "snapshots":  existing_snapshots,
    }

    with open(TMP_MANIFEST, "w") as f:
        json.dump(manifest, f)

    s3.upload_file(
        TMP_MANIFEST,
        static_bucket,
        manifest_key,
        ExtraArgs={"ContentType": "application/json", "CacheControl": "no-cache"},
    )
    print(f"[Transformer] Manifest: s3://{static_bucket}/{manifest_key} "
          f"({len(existing_snapshots)} snapshots)")


# ─── Handler principal ────────────────────────────────────────────────────────

def handler(event, context):
    # Recebe do Step Functions a saída do Extrator
    bronze_key    = event["bronze_key"]
    bronze_bucket = event["bucket"]
    static_bucket = os.environ["STATIC_BUCKET"]

    s3 = boto3.client("s3")

    # 1. Lê o JSON bruto da Bronze
    obj  = s3.get_object(Bucket=bronze_bucket, Key=bronze_key)
    dados = json.loads(obj["Body"].read())

    # 2. Calcula o timestamp normalizado (floor 5 min, sempre em UTC)
    now      = datetime.now(timezone.utc)
    ts_5min  = normalize_5min(now)
    date_str = ts_5min.strftime("%Y-%m-%d")
    hhmm     = ts_5min.strftime("%H%M")

    # 3. Flatten + enriquecimento H3 (r6–r9) + filtro de bbox SP
    rows = flatten_dados(dados, ts_5min)
    if not rows:
        print("[Transformer] Nenhum dado válido encontrado.")
        return {"status": "no_data", "rows_processed": 0}

    # 4. Carrega no DuckDB via JSON temporário
    with open(TMP_RAW, "w") as f:
        json.dump(rows, f)

    con = duckdb.connect()
    con.execute(f"CREATE TABLE silver AS SELECT * FROM read_json_auto('{TMP_RAW}')")

    # ── Silver: registro por veículo, bucket privado ───────────────────────────
    silver_key = f"silver/{date_str}/posicao_{hhmm}.parquet"
    con.execute(
        f"COPY silver TO '{TMP_SILVER}' (FORMAT PARQUET, COMPRESSION 'SNAPPY')"
    )
    s3.upload_file(TMP_SILVER, bronze_bucket, silver_key)
    print(f"[Transformer] Silver: s3://{bronze_bucket}/{silver_key} ({len(rows)} linhas)")

    # ── Gold/heatmap: agregado por H3 em todas as resoluções ──────────────────
    # Inclui r6 na agregação. O centróide lat/lon é a média das posições no hex.
    heatmap_key = f"data/gold/{date_str}/heatmap_{hhmm}.parquet"
    con.execute(f"""
        COPY (
            SELECT
                h3_r6,
                h3_r7,
                h3_r8,
                h3_r9,
                data_processamento,
                hora_5min,
                timestamp_5min,
                AVG(latitude)  AS latitude,
                AVG(longitude) AS longitude,
                COUNT(*)       AS contagem
            FROM silver
            WHERE h3_r8 IS NOT NULL
            GROUP BY
                h3_r6, h3_r7, h3_r8, h3_r9,
                data_processamento, hora_5min, timestamp_5min
        ) TO '{TMP_HEATMAP}' (FORMAT PARQUET, COMPRESSION 'SNAPPY')
    """)
    s3.upload_file(TMP_HEATMAP, static_bucket, heatmap_key)
    print(f"[Transformer] Gold/heatmap: s3://{static_bucket}/{heatmap_key}")

    # ── Gold/positions: posições brutas para o ScatterplotLayer ───────────────
    # Subset leve de colunas — o frontend não precisa de todos os campos Silver.
    positions_key = f"data/gold/{date_str}/positions_{hhmm}.parquet"
    con.execute(f"""
        COPY (
            SELECT
                prefixo,
                codigo_linha,
                destino_linha,
                latitude,
                longitude,
                acessivel,
                h3_r6,
                h3_r7,
                h3_r8,
                h3_r9,
                hora_5min,
                timestamp_5min
            FROM silver
            WHERE latitude IS NOT NULL AND longitude IS NOT NULL
        ) TO '{TMP_POSITIONS}' (FORMAT PARQUET, COMPRESSION 'SNAPPY')
    """)
    s3.upload_file(TMP_POSITIONS, static_bucket, positions_key)
    print(f"[Transformer] Gold/positions: s3://{static_bucket}/{positions_key}")

    # ── Manifest: atualiza índice do dia para o frontend descobrir slots ───────
    update_manifest(s3, static_bucket, date_str, hhmm)

    return {
        "status":        "success",
        "rows_processed": len(rows),
        "silver_key":    silver_key,
        "heatmap_key":   heatmap_key,
        "positions_key": positions_key,
    }