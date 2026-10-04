-- INE's 19 CCAA / autonomous-city codes and the seed's codes must be the same set.
with ine as (select distinct ccaa_code from {{ ref('stg_ine_ipv') }} where not is_national),
     seed as (select distinct ccaa_code from {{ ref('province_ccaa_mapping') }})
select coalesce(ine.ccaa_code, seed.ccaa_code) as ccaa_code,
       ine.ccaa_code is not null as in_ine, seed.ccaa_code is not null as in_seed
from ine full outer join seed using (ccaa_code)
where ine.ccaa_code is null or seed.ccaa_code is null
