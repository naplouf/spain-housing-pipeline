-- Quarterly -> annual aggregation of MIVAU appraised values.
--
-- Method: MEAN of the available quarters (not the Q4 value). INE's IPV is
-- published as an *annual average index*, so averaging the four MIVAU quarters
-- produces the like-for-like annual figure. It is also less noisy than a single
-- quarter for small provinces. quarters_available / is_complete_year expose
-- partial years (2026 = Q1-Q2 only; 'n.r' gaps in 2011-2013) so downstream
-- growth calculations can exclude them.
--
-- Covers both MIVAU grains so the annualisation rule lives in one place:
--   geo_level = 'province'           -> 52 provinces
--   geo_level = 'ccaa' / 'national'  -> MIVAU's own published aggregates

with province_quarters as (
    select
        'province' as geo_level, mivau_ccaa, mivau_province,
        year, valor_m2, value_flag
    from {{ ref('stg_mivau_valor_tasado') }}
),

aggregate_quarters as (
    select
        geo_level, mivau_ccaa, cast(null as string) as mivau_province,
        year, valor_m2, value_flag
    from {{ ref('stg_mivau_valor_tasado_ccaa') }}
),

all_quarters as (
    select * from province_quarters
    union all
    select * from aggregate_quarters
)

select
    geo_level,
    mivau_ccaa,
    mivau_province,
    year,
    round(avg(valor_m2), 1)                         as valor_m2_annual_mean,
    count(valor_m2)                                 as quarters_available,
    count(valor_m2) = 4                             as is_complete_year,
    countif(value_flag = 'not_representative')      as quarters_not_representative
from all_quarters
group by geo_level, mivau_ccaa, mivau_province, year
