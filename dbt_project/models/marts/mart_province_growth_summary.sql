-- One row per province: cumulative appraised-value growth over two windows,
-- compared with its own CCAA (MIVAU published) and with INE's CCAA index.
--   full window   : var('base_year')        -> var('last_full_year')  (2015 -> 2025)
--   recent window : var('recent_base_year') -> var('last_full_year')  (2020 -> 2025)
-- Uses annual means of complete years only.

{% set y0 = var('base_year') %}
{% set yr = var('recent_base_year') %}
{% set y1 = var('last_full_year') %}

with province_annual as (
    select a.*, m.province_code, m.province_iso_code, m.province_name, m.ccaa_code, m.ccaa_iso_code, m.ccaa_name,
           m.is_single_province_ccaa, m.is_autonomous_city
    from {{ ref('int_mivau_annual') }} as a
    inner join {{ ref('province_ccaa_mapping') }} as m using (mivau_province)
    where a.geo_level = 'province' and a.is_complete_year
),

province_pivot as (
    select
        province_code, province_iso_code, province_name, ccaa_code, ccaa_iso_code, ccaa_name,
        is_single_province_ccaa, is_autonomous_city,
        max(if(year = {{ y0 }}, valor_m2_annual_mean, null)) as valor_m2_base,
        max(if(year = {{ yr }}, valor_m2_annual_mean, null)) as valor_m2_recent_base,
        max(if(year = {{ y1 }}, valor_m2_annual_mean, null)) as valor_m2_last
    from province_annual
    group by 1, 2, 3, 4, 5, 6, 7, 8
),

ccaa_pivot as (
    select
        ccaa_code,
        max(if(year = {{ y0 }}, mivau_valor_m2, null))    as ccaa_valor_base,
        max(if(year = {{ yr }}, mivau_valor_m2, null))    as ccaa_valor_recent_base,
        max(if(year = {{ y1 }}, mivau_valor_m2, null))    as ccaa_valor_last,
        max(if(year = {{ y0 }}, ine_index_general, null)) as ine_base,
        max(if(year = {{ yr }}, ine_index_general, null)) as ine_recent_base,
        max(if(year = {{ y1 }}, ine_index_general, null)) as ine_last
    from {{ ref('mart_price_trends_ccaa') }}
    group by ccaa_code
),

national as (
    select * from ccaa_pivot where ccaa_code = '00'
),

growth as (
    select
        p.*,
        round(100 * (p.valor_m2_last / p.valor_m2_base - 1), 1)                     as growth_pct,
        round(100 * (pow(p.valor_m2_last / p.valor_m2_base, 1 / ({{ y1 }} - {{ y0 }})) - 1), 2) as cagr_pct,
        round(100 * (p.valor_m2_last / p.valor_m2_recent_base - 1), 1)              as growth_pct_recent,
        round(100 * (c.ccaa_valor_last / c.ccaa_valor_base - 1), 1)                 as ccaa_mivau_growth_pct,
        round(100 * (c.ccaa_valor_last / c.ccaa_valor_recent_base - 1), 1)          as ccaa_mivau_growth_pct_recent,
        round(100 * (c.ine_last / c.ine_base - 1), 1)                               as ccaa_ine_growth_pct,
        round(100 * (c.ine_last / c.ine_recent_base - 1), 1)                        as ccaa_ine_growth_pct_recent,
        round(100 * (n.ccaa_valor_last / n.ccaa_valor_base - 1), 1)                 as national_mivau_growth_pct,
        round(100 * (n.ine_last / n.ine_base - 1), 1)                               as national_ine_growth_pct
    from province_pivot as p
    left join ccaa_pivot as c using (ccaa_code)
    cross join national as n
),

final as (
    select
        province_code,
        province_iso_code,
        province_name,
        ccaa_code,
        ccaa_iso_code,
        ccaa_name,
        is_single_province_ccaa,
        is_autonomous_city,
        {{ y0 }}                                                    as base_year,
        {{ yr }}                                                    as recent_base_year,
        {{ y1 }}                                                    as last_year,
        valor_m2_base,
        valor_m2_recent_base,
        valor_m2_last,
        growth_pct,
        cagr_pct,
        growth_pct_recent,
        ccaa_mivau_growth_pct,
        ccaa_mivau_growth_pct_recent,
        ccaa_ine_growth_pct,
        ccaa_ine_growth_pct_recent,
        national_mivau_growth_pct,
        national_ine_growth_pct,
        round(growth_pct - ccaa_mivau_growth_pct, 1)                as growth_vs_ccaa_pp,
        round(growth_pct - national_mivau_growth_pct, 1)            as growth_vs_national_pp,
        rank() over (order by growth_pct desc)                      as growth_rank
    from growth
)

select
    *,
    case
        when growth_rank <= 5                                  then 'Top 5'
        when growth_rank > (select count(*) from final) - 5    then 'Bottom 5'
    end                                                         as rank_group
from final
