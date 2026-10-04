-- Every year 2007-2025 must have all 20 geographies (19 + national) from both sources.
select year, count(*) as n_geos, count(ine_index_general) as n_ine, count(mivau_valor_m2) as n_mivau
from {{ ref('mart_price_trends_ccaa') }}
where year between 2007 and {{ var('last_full_year') }}
group by year
having count(*) != 20 or count(ine_index_general) != 20 or count(mivau_valor_m2) != 20
