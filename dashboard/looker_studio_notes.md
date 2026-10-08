# Looker Studio dashboard — build notes

The dashboard reads only the three dbt marts in BigQuery (`spain-housing-pipeline.marts`).
All business logic lives in dbt. Looker Studio only formats and filters. Looker Studio
has no table relationships, so the marts are denormalised for it: ISO geo codes and
`growth_rank` / `rank_group` sit directly on the tables that need them, and no blends are required.

The same data model in Power BI terms: [`power_bi_notes.md`](power_bi_notes.md).

## 1. Create the report with data sources attached

Open this link while signed in to the Google account that owns the GCP project. It uses the
[Looker Studio Linking API](https://developers.google.com/looker-studio/integrate/linking-api)
to create a new report with the three marts already added as BigQuery data sources:

```
https://lookerstudio.google.com/reporting/create?c.mode=edit&r.reportName=Spain+Housing+Price+Divergence+2015-2025&ds.ds0.connector=bigQuery&ds.ds0.type=TABLE&ds.ds0.projectId=spain-housing-pipeline&ds.ds0.billingProjectId=spain-housing-pipeline&ds.ds0.datasetId=marts&ds.ds0.tableId=mart_province_growth_summary&ds.ds0.datasourceName=Province+growth+summary&ds.ds1.connector=bigQuery&ds.ds1.type=TABLE&ds.ds1.projectId=spain-housing-pipeline&ds.ds1.billingProjectId=spain-housing-pipeline&ds.ds1.datasetId=marts&ds.ds1.tableId=mart_price_trends_province&ds.ds1.datasourceName=Province+quarterly+trends&ds.ds2.connector=bigQuery&ds.ds2.type=TABLE&ds.ds2.projectId=spain-housing-pipeline&ds.ds2.billingProjectId=spain-housing-pipeline&ds.ds2.datasetId=marts&ds.ds2.tableId=mart_price_trends_ccaa&ds.ds2.datasourceName=CCAA+INE+vs+MIVAU
```

Click **Edit and share → Acknowledge and save**.

**Manual fallback** (if the link doesn't attach the sources): Create → Report → *Add data* →
BigQuery → My projects → `spain-housing-pipeline` → `marts` → pick a table. Repeat for each of the 3 tables.

**Data source settings** (Resource → Manage added data sources → Edit, for each source):
- *Data credentials*: **Owner's credentials**, so viewers don't need BigQuery access.
- *Data freshness*: 12 hours (the data changes quarterly).

## 2. Field setup

In each data source, set these field types and aggregations. Looker Studio defaults
numbers to SUM, which is wrong for indices and growth rates.

| Data source | Field | Type | Default aggregation |
|---|---|---|---|
| all | `*_pct`, `*_pp`, `*_rebased`, `ine_index_*`, `valor_m2*`, `mivau_valor_m2` | Number | **Average** |
| all | `year`, `growth_rank`, `province_code`, `ccaa_code` | Number / Text | **None** (dimension) |
| Province growth summary | `province_iso_code` | Geo → **Country subdivision (2nd level)** | – |
| Province growth summary | `ccaa_iso_code` | Geo → **Country subdivision (1st level)** | – |
| Province quarterly trends | `quarter_start_date` | Date → Year Month Day | – |

**Calculated fields** (Province growth summary):

| Name | Formula | Type |
|---|---|---|
| `Growth 2015-2025` | `growth_pct / 100` | Numeric → Percent |
| `Growth 2020-2025` | `growth_pct_recent / 100` | Numeric → Percent |
| `Growth vs own CCAA (pp)` | `growth_vs_ccaa_pp` | Number, 1 decimal |
| `National MIVAU growth` | `national_mivau_growth_pct / 100` | Numeric → Percent |

**Calculated field** (CCAA INE vs MIVAU):

| Name | Formula | Type |
|---|---|---|
| `Year (date)` | `DATE(year, 1, 1)` | Date → Year |

## 3. Pages

Theme: *Simple* (light), a single accent colour, and a 1280 × 900 canvas. Put this footer text box on every page:

> *INE IPV = hedonic transaction-price index (base 2025 = 100). MIVAU = average bank-appraised value (€/m²).
> They measure different things and are compared only as growth (both rebased to 2015 = 100), never on one raw axis.*

### Page 1: Where prices grew (2015 → 2025)
Data source: **Province growth summary**.

| Element | Chart | Setup |
|---|---|---|
| KPI cards ×3 | Scorecard | `National MIVAU growth` (+44.2%); `national_ine_growth_pct` labelled "INE index growth, national" (79.9); text card: "Spread top→bottom province: 91 pp" |
| Map | **Google Maps → Filled map** | Location = `province_iso_code`, Colour metric = `Growth 2015-2025`, diverging colours (red < 0 → white ≈ 0.44 → green). Tooltip: `province_name`, `ccaa_name`, `Growth vs own CCAA (pp)` |
| Ranking | **Bar chart (horizontal)** | Dimension `province_name`, Metric `Growth 2015-2025`, sort descending, 52 bars, *Style → Reference line*: metric `National MIVAU growth`, label "Spain +44%" |
| Control | Drop-down list | `ccaa_name` (multi-select) |

> **Map note:** Google Maps filled areas need Looker Studio to recognise Spanish provinces as
> 2nd-level subdivisions. If the polygons don't fill, use `ccaa_iso_code` (1st level) with
> `ccaa_mivau_growth_pct` for a CCAA-level map, and keep the province detail in the bar chart. The ranked bar chart is
> the authoritative province view either way, and Ceuta/Melilla are too small to see on any map.
>
> *As built:* Looker Studio did not fill Spanish province polygons, so the live report uses a
> **bubble** layer at province locations coloured by `ccaa_mivau_growth_pct` (regional growth).
> Zoom the map viewport to Iberia + Canarias so the Canary Islands bubbles are visible.

### Page 2: Top 5 vs bottom 5 provinces
Data source: **Province quarterly trends**.

| Element | Chart | Setup |
|---|---|---|
| Trend | **Time series** | Dimension `quarter_start_date` (Year Quarter), Breakdown `province_name`, Metric `index_rebased` (Average), chart filter **`rank_group` is not null** and **`year` ≥ 2015**. Title: *"Appraised value index, 2015 = 100: five fastest vs five slowest provinces"* |
| Colours | – | Top 5 (Illes Balears, Málaga, Madrid, Santa Cruz de Tenerife, Valencia) warm. Bottom 5 (Jaén, Zamora, Ciudad Real, Soria, Palencia) cool. |
| Table | Table | Dimensions `rank_group`, `province_name`, `province_note`. Metrics `valor_m2` (filtered to the latest quarter), `yoy_pct`. Filter `rank_group` not null and `quarter_start_date` = 2026-04-01 |

Why `index_rebased` and not `valor_m2`: Madrid is ~3,700 €/m² and Palencia ~1,000 €/m². On a raw
€ axis the level gap hides the growth story. Rebasing to 2015 = 100 shows growth directly.

### Page 3: INE price index vs MIVAU appraisals, by CCAA
Data source: **CCAA INE vs MIVAU**. Page-level filter `year` between 2015 and 2025.

| Element | Chart | Setup |
|---|---|---|
| Control | Drop-down list | `ccaa_name`, **single select**, default **Nacional**. Every chart on the page must show one geography; summing indices across regions is meaningless. |
| Normalised trend (primary) | **Time series** | Dimension `Year (date)`. Metrics `ine_index_rebased`, `mivau_index_rebased` (Average). One shared axis is valid because both = 100 in 2015. Title: *"Growth since 2015 (2015 = 100): transaction-price index vs appraised value"* |
| Raw units (dual axis) | **Time series** | Dimension `Year (date)`. Metric 1 `ine_index_general` on the **left** axis (title "INE index, 2025 = 100"). Metric 2 `mivau_valor_m2` → *Style → Series #2 → Axis: Right* (title "MIVAU €/m²"). Never put both on one axis. |
| Divergence | **Bar chart** | Dimension `ccaa_name`, Metric `rebased_gap_pts`, chart filter `year` = 2025, sort ascending. Title: *"How far appraisals lag the price index (index points, 2025)"*. It must *not* follow the drop-down: select the drop-down plus the two time series → **Arrange → Group**. A control only filters charts in its own group. |

## 4. Share and screenshot

1. **Share → Manage access → Anyone with the link can view** (only if you want it public; the data is public INE/MIVAU data).
2. Export screenshots of each page into `dashboard/screenshots/` as `01_province_growth.png`,
   `02_top_bottom_5.png`, `03_ine_vs_mivau.png`, then add the report URL to the README.
