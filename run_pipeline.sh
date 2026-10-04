#!/usr/bin/env bash
# End-to-end run: raw files -> parsed parquet -> BigQuery raw -> dbt marts (+ tests, docs).
# Prereqs: see README "Setup" (gcloud ADC login, ~/.dbt/profiles.yml, pip install -r ingestion/requirements.txt)
set -euo pipefail
cd "$(dirname "$0")"

echo "== 1/4 Parse INE IPV (79540.csv)";               python ingestion/parse_ine_ipv.py
echo "== 2/4 Parse MIVAU valor tasado (35101000.XLS)";  python ingestion/parse_mivau_valor_tasado.py
echo "== 3/4 Load to BigQuery raw dataset";             python ingestion/load_to_bigquery.py
echo "== 4/4 dbt seed + run + test";                    (cd dbt_project && dbt build && dbt docs generate)
echo "Done. Marts are in the BigQuery 'marts' dataset."
