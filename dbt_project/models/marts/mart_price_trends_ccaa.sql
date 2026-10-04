-- INE price index vs MIVAU appraised value, side by side, per CCAA and year.
--
-- The two sources measure DIFFERENT things:
--   INE IPV        = hedonic price index of transaction prices (base 2025 = 100)
--   MIVAU valor_m2 = average appraised value in EUR/m2 (bank valuations)
-- Their levels must never share an axis. They are made comparable only as
-- growth: both are rebased to var('base_year') = 100 (the *_rebased columns),
-- and rebased_gap_pts measures how far the two trends have diverged.
-- Grain: ccaa_code x year (ccaa_code '00' = national benchmark).

{% set base_year = var('base_year') %}

with ine as (
    select
        ccaa_code,
        year,
        max(if(index_type = 'general'     and metric_type = 'index', value, null))                as ine_index_general,
        max(if(index_type = 'new'         and metric_type = 'index', value, null))                as ine_index_new,
        max(if(index_type = 'second_hand' and metric_type = 'index', value, null))                as ine_index_second_hand,
        max(if(index_type = 'general'     and metric_type = 'annual_variation_pct', value, null)) as ine_annual_variation_pct
    from {{ ref('stg_ine_ipv') }}
    group by ccaa_code, year
),

mivau as (
    select * from {{ ref('int_mivau_by_ccaa') }}
),

ccaa_attributes as (
    select distinct ccaa_code, ccaa_name, is_single_province_ccaa, is_autonomous_city
    from mivau
),

ccaa_iso as (
    select distinct ccaa_code, ccaa_iso_code
    from {{ ref('province_ccaa_mapping') }}
),

joined as (
    select
        coalesce(ine.ccaa_code, mivau.ccaa_code)    as ccaa_code,
        coalesce(ine.year, mivau.year)              as year,
        ine.ine_index_general,
        ine.ine_index_new,
        ine.ine_index_second_hand,
        ine.ine_annual_variation_pct,
        mivau.valor_m2                              as mivau_valor_m2,
        mivau.valor_source                          as mivau_valor_source,
        mivau.quarters_available                    as mivau_quarters_available,
        mivau.is_complete_year                      as mivau_is_complete_year,
        mivau.province_simple_mean                  as mivau_province_simple_mean,
        mivau.n_provinces
    from ine
    full outer join mivau using (ccaa_code, year)
),

with_growth as (
    select
        j.*,
        -- YoY only between two complete years, so 2026 (Q1-Q2) never shows as growth
        if(j.mivau_is_complete_year and lag(j.mivau_is_complete_year) over w,
           round(100 * (j.mivau_valor_m2 / lag(j.mivau_valor_m2) over w - 1), 2),
           null)                                                            as mivau_yoy_pct,
        round(100 * j.ine_index_general
              / max(if(j.year = {{ base_year }}, j.ine_index_general, null)) over (partition by j.ccaa_code), 2)
                                                                            as ine_index_rebased,
        if(j.mivau_is_complete_year,
           round(100 * j.mivau_valor_m2
                 / max(if(j.year = {{ base_year }}, j.mivau_valor_m2, null)) over (partition by j.ccaa_code), 2),
           null)                                                            as mivau_index_rebased
    from joined as j
    window w as (partition by j.ccaa_code order by j.year)
)

select
    g.ccaa_code,
    a.ccaa_name,
    iso.ccaa_iso_code,
    g.year,
    g.ccaa_code = '00'                                      as is_national,
    a.is_single_province_ccaa,
    a.is_autonomous_city,
    g.n_provinces,
    g.ine_index_general,
    g.ine_index_new,
    g.ine_index_second_hand,
    g.ine_annual_variation_pct,
    g.mivau_valor_m2,
    g.mivau_valor_source,
    g.mivau_quarters_available,
    g.mivau_is_complete_year,
    g.mivau_province_simple_mean,
    g.mivau_yoy_pct,
    {{ base_year }}                                         as rebase_year,
    g.ine_index_rebased,
    g.mivau_index_rebased,
    round(g.mivau_index_rebased - g.ine_index_rebased, 2)   as rebased_gap_pts
from with_growth as g
left join ccaa_attributes as a using (ccaa_code)
left join ccaa_iso as iso using (ccaa_code)
