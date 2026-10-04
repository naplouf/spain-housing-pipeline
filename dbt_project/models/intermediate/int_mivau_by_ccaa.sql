-- MIVAU annual appraised value at INE CCAA grain (ccaa_code x year), plus the
-- national benchmark as ccaa_code '00'.
--
-- Headline value (valor_m2): MIVAU's OWN published CCAA figure. MIVAU builds it
-- from all appraisals in the region, so it is implicitly volume-weighted. A plain
-- average of province values would give Teruel the same weight as Zaragoza, and
-- we have no transaction counts to weight it ourselves.
--
-- Province -> CCAA rollup via the seed is still computed, as a cross-check
-- (province_simple_mean) and to attach INE codes:
--   * regular CCAAs       -> published CCAA row, joined on the MIVAU header label
--   * Ceuta / Melilla     -> MIVAU publishes them under ONE combined header
--                            "Ceuta y Melilla", but INE treats them as two
--                            autonomous cities (18, 19). The seed hardcodes the
--                            split; each city's own row becomes its CCAA value.
--                            The combined "Ceuta y Melilla" row has no INE
--                            counterpart and is not used.
--   * TOTAL NACIONAL      -> ccaa_code '00'

with annual as (
    select * from {{ ref('int_mivau_annual') }}
),

mapping as (
    select * from {{ ref('province_ccaa_mapping') }}
),

ccaa_lookup as (
    select distinct mivau_ccaa, ccaa_code, ccaa_name
    from mapping
    where not is_autonomous_city
),

published_ccaa as (
    select
        l.ccaa_code, l.ccaa_name, a.year,
        a.valor_m2_annual_mean as valor_m2, a.quarters_available, a.is_complete_year,
        'mivau_published_ccaa' as valor_source
    from annual as a
    inner join ccaa_lookup as l using (mivau_ccaa)
    where a.geo_level = 'ccaa'
),

autonomous_cities as (
    select
        m.ccaa_code, m.ccaa_name, a.year,
        a.valor_m2_annual_mean, a.quarters_available, a.is_complete_year,
        'mivau_city_row'
    from annual as a
    inner join mapping as m using (mivau_province)
    where a.geo_level = 'province' and m.is_autonomous_city
),

national as (
    select
        '00', 'Nacional', year,
        valor_m2_annual_mean, quarters_available, is_complete_year,
        'mivau_total_nacional'
    from annual
    where geo_level = 'national'
),

ccaa_series as (
    select * from published_ccaa
    union all select * from autonomous_cities
    union all select * from national
),

province_rollup as (
    select
        m.ccaa_code,
        a.year,
        round(avg(a.valor_m2_annual_mean), 1)      as province_simple_mean,
        count(*)                                   as n_provinces,
        count(a.valor_m2_annual_mean)              as n_provinces_with_data,
        logical_and(m.is_single_province_ccaa)     as is_single_province_ccaa,
        logical_and(m.is_autonomous_city)          as is_autonomous_city
    from annual as a
    inner join mapping as m using (mivau_province)
    where a.geo_level = 'province'
    group by m.ccaa_code, a.year
)

select
    s.ccaa_code,
    s.ccaa_name,
    s.year,
    s.valor_m2,
    s.valor_source,
    s.quarters_available,
    s.is_complete_year,
    r.province_simple_mean,
    r.n_provinces,
    r.n_provinces_with_data,
    coalesce(r.is_single_province_ccaa, false)     as is_single_province_ccaa,
    coalesce(r.is_autonomous_city, false)          as is_autonomous_city,
    s.ccaa_code = '00'                             as is_national
from ccaa_series as s
left join province_rollup as r using (ccaa_code, year)
