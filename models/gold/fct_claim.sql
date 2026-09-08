-- GOLD — claim fact. Grain: one row per claim. 12,000 of them.
--
-- THIS MODEL IS WHY SCD2 EXISTS. The join to dim_policy is a POINT-IN-TIME join:
--
--     on  c.policy_id = p.policy_natural_key
--     and c.claim_date between p.valid_from and p.valid_to
--
-- A claim filed on 5 August joins to the premium that was in force on 5 August, not
-- the one in force today. Join to is_current instead and every historical report
-- silently restates itself every time a policy changes.
--
-- Two things to be careful about:
--
--   1. 206 claims have no usable date, so they cannot be placed in time. They keep an
--      UNKNOWN policy_key rather than being dropped — losing rows in a join is the
--      single most common way a warehouse quietly starts lying. The reconciliation
--      test below exists precisely to catch that.
--
--   2. LEFT JOIN, not inner. An inner join here would delete those 206 claims and the
--      row count would still look plausible.

with claims as (select * from {{ ref('silver_claims') }}),
     policies as (select * from {{ ref('dim_policy') }})

select
    c.claim_id,
    coalesce(p.policy_key, 'UNKNOWN')  as policy_key,
    coalesce(p.broker_key, 'UNKNOWN')  as broker_key,
    c.policy_id                        as policy_natural_key,
    c.claim_date,
    c.claim_date_is_valid,
    c.amount,
    c.status,
    p.policy_key is null               as is_unmatched
from claims c
left join policies p
       on c.policy_id  = p.policy_natural_key
      and c.claim_date between p.valid_from and p.valid_to
