-- MIVAU appraised value per province and quarter, with YoY growth.
-- Grain: province_code x year x quarter. Units: EUR/m2 (appraised value, not an index).
-- Single-province CCAAs are kept as regular rows and flagged (province_note);
-- their value is identical to the CCAA value by construction.

{% set base_year = var('base_year') %}

with quarterly as (
    select * from {{ ref('stg_mivau_valor_tasado') }}
),

mapping as (
    select * from {{ ref('province_ccaa_mapping') }}
),

growth_summary as (
    select province_code, growth_rank, rank_group
    from {{ ref('mart_province_growth_summary') }}
),

base_year_mean as (
    select mivau_province, valor_m2_annual_mean as base_valor_m2
    from {{ ref('int_mivau_annual') }}
    where geo_level = 'province' and year = {{ base_year }}
)

select
    m.province_code,
    m.province_iso_code,
    m.province_name,
    q.mivau_province,
    m.ccaa_code,
    m.ccaa_iso_code,
    m.ccaa_name,
    q.year,
    q.quarter,
    q.quarter_start_date,
    q.valor_m2,
    q.value_flag,
    prior.valor_m2                                              as valor_m2_prior_year,
    round(100 * (q.valor_m2 / prior.valor_m2 - 1), 2)           as yoy_pct,
    {{ base_year }}                                             as rebase_year,
    round(100 * q.valor_m2 / b.base_valor_m2, 2)                as index_rebased,
    m.is_single_province_ccaa,
    m.is_autonomous_city,
    case
        when m.is_single_province_ccaa
            then 'Single-province CCAA: value is the CCAA row published by MIVAU (province = CCAA)'
        when m.is_autonomous_city
            then 'Autonomous city: listed under MIVAU header "Ceuta y Melilla", mapped to its own INE code'
        else 'Province within a multi-province CCAA'
    end                                                         as province_note,
    gs.growth_rank,
    gs.rank_group
from quarterly as q
inner join mapping as m on m.mivau_province = q.mivau_province
left join quarterly as prior
    on  prior.mivau_province = q.mivau_province
    and prior.year = q.year - 1
    and prior.quarter = q.quarter
left join base_year_mean as b on b.mivau_province = q.mivau_province
left join growth_summary as gs on gs.province_code = m.province_code
