-- For single-province CCAAs and autonomous cities, the CCAA value must equal the
-- (only) province value - confirms they were neither dropped nor averaged.
select ccaa_code, year, valor_m2, province_simple_mean
from {{ ref('int_mivau_by_ccaa') }}
where (is_single_province_ccaa or is_autonomous_city)
  and abs(coalesce(valor_m2, -1) - coalesce(province_simple_mean, -1)) > 0.001
