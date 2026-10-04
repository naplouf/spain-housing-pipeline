-- Both rebased series must be exactly 100 in the rebase year for every geography.
select ccaa_code, ine_index_rebased, mivau_index_rebased
from {{ ref('mart_price_trends_ccaa') }}
where year = {{ var('base_year') }}
  and (abs(ine_index_rebased - 100) > 0.001 or abs(mivau_index_rebased - 100) > 0.001
       or ine_index_rebased is null or mivau_index_rebased is null)
