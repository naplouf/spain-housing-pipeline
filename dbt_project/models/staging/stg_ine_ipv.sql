-- INE IPV: one row per CCAA x index type x metric x year.
-- Translates INE's English header labels into stable codes; no aggregation.
select
    ccaa_code,
    ccaa                                   as ccaa_name_ine,
    ccaa_code = '00'                       as is_national,
    case index_type
        when 'General'              then 'general'
        when 'New dwelling'         then 'new'
        when 'Second-hand dwelling' then 'second_hand'
    end                                    as index_type,
    case metric_type
        when 'Annual average index' then 'index'
        when 'Annual variation'     then 'annual_variation_pct'
    end                                    as metric_type,
    cast(year as int64)                    as year,
    cast(value as float64)                 as value
from {{ source('raw', 'ine_ipv') }}
