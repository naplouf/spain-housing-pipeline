"""Load the parsed staging files into the BigQuery `raw` dataset.

Idempotent: each table is replaced (WRITE_TRUNCATE) on every run.
Auth uses Application Default Credentials (`gcloud auth application-default login`);
no keys live in the repo.

Env vars:
  GCP_PROJECT   target project (default: gcloud's default project)
  BQ_LOCATION   dataset location (default: EU)
  BQ_RAW_DATASET  (default: raw)
"""
from pathlib import Path
import os

import pandas as pd
from google.cloud import bigquery

ROOT = Path(__file__).resolve().parents[1]
STAGING = ROOT / "data" / "staging"
LOCATION = os.environ.get("BQ_LOCATION", "EU")
DATASET = os.environ.get("BQ_RAW_DATASET", "raw")

F = bigquery.SchemaField
TABLES = {
    "ine_ipv": (
        "ine_ipv.parquet",
        [
            F("ccaa_code", "STRING", "REQUIRED", description="INE CCAA code, '00' = Nacional"),
            F("ccaa", "STRING", "REQUIRED", description="CCAA name as published by INE"),
            F("index_type", "STRING", "REQUIRED"),
            F("metric_type", "STRING", "REQUIRED"),
            F("year", "INT64", "REQUIRED"),
            F("value", "FLOAT64", description="Index (base 2025=100) or annual % variation"),
        ],
    ),
    "mivau_valor_tasado": (
        "mivau_valor_tasado.parquet",
        [
            F("ccaa", "STRING", "REQUIRED", description="MIVAU CCAA header label"),
            F("province", "STRING", "REQUIRED", description="MIVAU province label"),
            F("year", "INT64", "REQUIRED"),
            F("quarter", "INT64", "REQUIRED"),
            F("valor_m2", "FLOAT64", description="Average appraised value, EUR/m2"),
            F("is_single_province_ccaa", "BOOL", "REQUIRED"),
            F("value_flag", "STRING", description="no_data | not_representative | NULL"),
            F("source_sheet", "STRING", "REQUIRED"),
        ],
    ),
    "mivau_valor_tasado_ccaa": (
        "mivau_valor_tasado_ccaa.parquet",
        [
            F("geo_level", "STRING", "REQUIRED", description="national | ccaa"),
            F("ccaa", "STRING", "REQUIRED"),
            F("year", "INT64", "REQUIRED"),
            F("quarter", "INT64", "REQUIRED"),
            F("valor_m2", "FLOAT64"),
            F("value_flag", "STRING"),
        ],
    ),
}


def main():
    client = bigquery.Client(project=os.environ.get("GCP_PROJECT"), location=LOCATION)
    dataset_id = f"{client.project}.{DATASET}"
    ds = bigquery.Dataset(dataset_id)
    ds.location = LOCATION
    ds.description = "Raw parsed INE IPV and MIVAU valor tasado files (see ingestion/)"
    client.create_dataset(ds, exists_ok=True)
    print(f"Dataset {dataset_id} ({LOCATION}) ready")

    for table, (filename, schema) in TABLES.items():
        df = pd.read_parquet(STAGING / filename)
        df = df[[f.name for f in schema]]
        job_config = bigquery.LoadJobConfig(
            schema=schema, write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE
        )
        table_id = f"{dataset_id}.{table}"
        client.load_table_from_dataframe(df, table_id, job_config=job_config).result()
        n = client.get_table(table_id).num_rows
        assert n == len(df), f"{table_id}: loaded {n} rows, expected {len(df)}"
        print(f"  loaded {table_id:<55} {n:>6,} rows")


if __name__ == "__main__":
    main()
