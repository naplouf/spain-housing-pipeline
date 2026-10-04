-- MIVAU's own published CCAA / national aggregates: one row per geography x quarter.
select
    geo_level,
    ccaa                                    as mivau_ccaa,
    cast(year as int64)                     as year,
    cast(quarter as int64)                  as quarter,
    date(year, 3 * quarter - 2, 1)          as quarter_start_date,
    cast(valor_m2 as float64)               as valor_m2,
    value_flag
from {{ source('raw', 'mivau_valor_tasado_ccaa') }}
