-- The CCAA header and single-province flag the parser derived structurally from the
-- sheet must agree with the hand-written seed.
select distinct m.mivau_province, m.mivau_ccaa, s.mivau_ccaa as seed_ccaa,
       m.is_single_province_ccaa, s.is_single_province_ccaa as seed_flag
from {{ ref('stg_mivau_valor_tasado') }} as m
inner join {{ ref('province_ccaa_mapping') }} as s using (mivau_province)
where m.mivau_ccaa != s.mivau_ccaa
   or m.is_single_province_ccaa != s.is_single_province_ccaa
