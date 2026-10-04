# Power BI dashboard — build notes

> The live dashboard is currently built in Looker Studio ([`looker_studio_notes.md`](looker_studio_notes.md)).
> This file documents the same data model and measures for a Power BI rebuild (Power BI Desktop is Windows-only).

The dashboard reads only the three dbt marts in the BigQuery `marts` dataset. All
business logic (annualisation, CCAA rollup, rebasing, growth windows) lives in dbt.
Power BI only adds display measures.

## 1. Connect

1. **Get Data → Google BigQuery** → sign in with the Google account that owns the GCP project.
2. Navigate to `spain-housing-pipeline` → `marts` and select:
   - `mart_province_growth_summary` (52 rows, one per province)
   - `mart_price_trends_province` (6,552 rows, province × quarter)
   - `mart_price_trends_ccaa` (640 rows, CCAA × year)
3. Choose **Import** mode. The data is small and changes quarterly, so DirectQuery adds
   cost and latency for no benefit. Refresh after each `./run_pipeline.sh`.

> No credentials are stored in the repo. Power BI keeps its own OAuth token for BigQuery.

## 2. Model

| From | To | Cardinality |
|---|---|---|
| `mart_price_trends_province[province_code]` | `mart_province_growth_summary[province_code]` | many → one, single direction |

`mart_price_trends_ccaa` stays unrelated. It sits at a different grain (CCAA × year)
and is only used on page 3.

**Column settings**
- `mart_province_growth_summary[province_name]` → Data category **State or Province**.
- Add a calculated column so the map geocodes inside Spain, not e.g. "Valencia, Venezuela":
  ```DAX
  Map Location = mart_province_growth_summary[province_name] & ", Spain"
  ```
- `province_iso_code` / `ccaa_iso_code` (ISO 3166-2, e.g. `ES-MA`) are available as unambiguous keys, e.g. for a Shape Map with a custom TopoJSON of Spanish provinces.
- Mark `quarter_start_date` as a Date column. Hide the `mivau_*` raw label columns and the `rebase_year` columns from report view.

**Measures**
```DAX
Growth % 2015-2025      = AVERAGE ( mart_province_growth_summary[growth_pct] ) / 100
Growth vs CCAA (pp)     = AVERAGE ( mart_province_growth_summary[growth_vs_ccaa_pp] )
National MIVAU Growth % = MAX ( mart_province_growth_summary[national_mivau_growth_pct] ) / 100
```
`rank_group` ('Top 5' / 'Bottom 5') and `growth_rank` are computed in dbt and exist on both
`mart_province_growth_summary` and `mart_price_trends_province`, so no DAX is needed for the page 2 filter.

## 3. Pages

Every page carries the same footer text box:
> *INE IPV = hedonic transaction-price index (base 2025 = 100). MIVAU = average bank-appraised value (€/m²).
> They measure different things and are compared only as growth (both rebased to 2015 = 100).*

### Page 1: "Where prices grew" (province level)
- **Filled map**: Location = `Map Location`, colour saturation = `Growth % 2015-2025`
  (diverging: red below 0, neutral at national +44%, dark green at the top).
  Tooltip: `province_name`, `ccaa_name`, `valor_m2_base`, `valor_m2_last`, `growth_pct`, `growth_vs_ccaa_pp`.
  (Ceuta and Melilla are tiny on the map, so the bar chart below is the authoritative view.)
- **Clustered bar chart** (52 bars, sorted descending): Y = `province_name`, X = `growth_pct`.
  Analytics pane → **Constant line** at `national_mivau_growth_pct` (44.2), labelled "Spain (MIVAU)".
  Colour bars by `ccaa_name`, or conditional format on `growth_vs_ccaa_pp` (above/below its own region).
- **Cards**: national MIVAU growth +44.2%, national INE growth +79.9%, top-vs-bottom spread.
- **Slicer**: `ccaa_name`.

### Page 2: "Top 5 vs bottom 5 provinces" (time series)
- **Line chart**: X = `mart_price_trends_province[quarter_start_date]` (2015 Q1 → 2026 Q2),
  Y = `index_rebased` (2015 = 100), Legend = `province_name`.
  Visual filter: `mart_price_trends_province[rank_group]` is not blank (10 lines).
  Use warm colours for the Top 5 and cool colours for the Bottom 5.
- **Why `index_rebased` and not `valor_m2`:** Madrid is ~3,700 €/m² and Palencia ~1,000 €/m².
  On a raw € axis the growth story is hidden by level differences. Rebasing to 2015 = 100 puts
  every province on the same "growth since 2015" scale.
- Secondary table: `province_name`, `valor_m2_last`, `growth_pct`, `growth_pct_recent`, `province_note`
  (the note shows which rows are single-province CCAAs).

### Page 3: "INE index vs MIVAU appraisals" (CCAA level)
- **Line chart A (primary, normalised)**: X = `year` (filter 2015–2025), Y = `ine_index_rebased`
  and `mivau_index_rebased`. Both are 100 in 2015, so a shared axis is legitimate.
  Title: *"Growth since 2015 (2015 = 100): transaction-price index vs appraised value"*.
  Single-select slicer on `ccaa_name` (default **Nacional**).
- **Line chart B (dual axis, raw units)**: a **Line and clustered column chart** or a line chart with
  a **secondary Y-axis**: `ine_index_general` on the left axis (titled "INE index, 2025 = 100"),
  `mivau_valor_m2` on the right axis (titled "MIVAU €/m²"). Never put these two on one axis.
- **Bar chart**: Y = `ccaa_name`, X = `rebased_gap_pts` for `year = 2025`, sorted. It shows how far
  appraisals lag transaction prices in each region.

## 4. Screenshots

Export each page (File → Export → PDF, or a screenshot) into `dashboard/screenshots/`:
`01_province_growth.png`, `02_top_bottom_5.png`, `03_ine_vs_mivau.png`.
