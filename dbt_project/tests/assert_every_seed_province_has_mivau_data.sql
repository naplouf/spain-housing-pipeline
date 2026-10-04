-- Reverse of the staging relationships test: every seed province must appear in the
-- MIVAU data with all quarters, so a typo in the seed cannot silently drop a province.
select s.mivau_province, count(m.mivau_province) as n_quarters
from {{ ref('province_ccaa_mapping') }} as s
left join {{ ref('stg_mivau_valor_tasado') }} as m using (mivau_province)
group by s.mivau_province
having count(m.mivau_province) != (select count(distinct format('%d-%d', year, quarter))
                                   from {{ ref('stg_mivau_valor_tasado') }})
