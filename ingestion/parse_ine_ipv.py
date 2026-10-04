"""Parse INE Índice de Precios de Vivienda (table 79540, base 2025) into a long table.

Input : data/raw/79540.csv  (tab-separated, UTF-8 with BOM, decimal comma,
        English headers / Spanish values, annual 2007-2025, CCAA level only)
Output: data/staging/ine_ipv.parquet with columns
        ccaa_code, ccaa, index_type, metric_type, year, value

Only structural cleanup happens here (encoding, decimal comma, splitting the
INE code prefix off the CCAA label). Renaming values to canonical codes is
left to dbt staging so the raw layer stays close to the source.
"""
from pathlib import Path
import sys

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "data" / "raw" / "79540.csv"
OUT = ROOT / "data" / "staging" / "ine_ipv.parquet"

EXPECTED_COLUMNS = [
    "Autonomous Communities and Cities", "Index type",
    "Indices and rates", "Periodo", "Total",
]
# 17 CCAA + Ceuta + Melilla + Nacional = 20 geography values
EXPECTED_GEO_COUNT = 20
EXPECTED_INDEX_TYPES = {"General", "New dwelling", "Second-hand dwelling"}
EXPECTED_METRICS = {"Annual average index", "Annual variation"}


def parse() -> pd.DataFrame:
    raw = pd.read_csv(SRC, sep="\t", encoding="utf-8-sig", dtype=str)
    if list(raw.columns) != EXPECTED_COLUMNS:
        sys.exit(f"Unexpected columns in {SRC.name}: {list(raw.columns)}")

    geo = raw["Autonomous Communities and Cities"].str.strip()
    # "01 Andalucía" -> code "01", name "Andalucía"; "Nacional" has no code -> "00"
    parts = geo.str.extract(r"^(?:(\d{2})\s+)?(.+)$")
    df = pd.DataFrame({
        "ccaa_code": parts[0].fillna("00"),
        "ccaa": parts[1],
        "index_type": raw["Index type"].str.strip(),
        "metric_type": raw["Indices and rates"].str.strip(),
        "year": raw["Periodo"].astype(int),
        # decimal comma -> float; INE uses no thousands separator in this file
        "value": pd.to_numeric(raw["Total"].str.replace(",", ".", regex=False), errors="raise"),
    })

    # --- validation -------------------------------------------------------
    geos = df[["ccaa_code", "ccaa"]].drop_duplicates().sort_values("ccaa_code")
    assert len(geos) == EXPECTED_GEO_COUNT, f"expected {EXPECTED_GEO_COUNT} geographies, got {len(geos)}"
    assert set(df.index_type) == EXPECTED_INDEX_TYPES, set(df.index_type)
    assert set(df.metric_type) == EXPECTED_METRICS, set(df.metric_type)
    assert not df.duplicated(["ccaa_code", "index_type", "metric_type", "year"]).any()

    print(f"Loaded {len(df)} rows, years {df.year.min()}-{df.year.max()}")
    print(f"\n{len(geos)} geography values (17 CCAA + Ceuta + Melilla + Nacional):")
    for code, name in geos.itertuples(index=False):
        print(f"  {code}  {name}")
    print("\nRows per index type x metric:")
    print(df.groupby(["index_type", "metric_type"]).size().to_string())
    nulls = df[df.value.isna()].groupby(["ccaa", "index_type"]).size()
    print(f"\nNull values: {df.value.isna().sum()} (INE does not publish these series):")
    print(nulls.to_string())
    base = df.query("ccaa_code=='00' and index_type=='General' and metric_type=='Annual average index' and year==2025")
    print(f"\nBase check - Nacional General index 2025 = {base.value.item()} (expect 100)")
    return df


if __name__ == "__main__":
    out = parse()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.to_parquet(OUT, index=False)
    print(f"\nWrote {OUT.relative_to(ROOT)}")
