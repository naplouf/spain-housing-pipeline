-- MIVAU valor tasado: one row per province x quarter (EUR/m2). Typing only.
select
    ccaa                                    as mivau_ccaa,
    province                                as mivau_province,
    cast(year as int64)                     as year,
    cast(quarter as int64)                  as quarter,
    date(year, 3 * quarter - 2, 1)          as quarter_start_date,
    cast(valor_m2 as float64)               as valor_m2,
    value_flag,
    is_single_province_ccaa,
    source_sheet
from {{ source('raw', 'mivau_valor_tasado') }}
