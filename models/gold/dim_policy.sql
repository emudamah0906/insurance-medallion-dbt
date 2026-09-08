-- GOLD — policy dimension, SCD Type 2. One row per policy PER VERSION.
--
-- The surrogate key hashes policy_id together with valid_from, so each version gets
-- its own key. That is what lets a fact row point at a specific version of a policy
-- rather than at "the policy" in the abstract.
select
    to_hex(md5(concat(policy_id, '|', cast(valid_from as string)))) as policy_key,
    policy_id                                                      as policy_natural_key,
    to_hex(md5(broker_id))                                         as broker_key,
    product,
    premium,
    status,
    start_date,
    end_date,
    valid_from,
    valid_to,
    is_current
from {{ ref('silver_policies') }}
