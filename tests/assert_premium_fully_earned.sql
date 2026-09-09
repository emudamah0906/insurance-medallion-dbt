-- ============================================================================
-- EARNED PREMIUM CLOSURE GATE.
--
-- Spreading a number across months is exactly where it quietly leaks. If the
-- pro-rata is off by a day at a month boundary, every month is slightly wrong and
-- every month still looks entirely plausible.
--
-- So: for any policy version whose whole term falls inside the month window, the
-- monthly earned amounts must add back up to the written premium. Premium in equals
-- premium out. Same closure idea as the volume gate in the quarry project.
--
-- NOTE ON THE SQL: the aggregation happens in the CTE and the filtering happens
-- outside it. An earlier version put both in a HAVING clause and BigQuery rejected it
-- with "aggregations of aggregations are not allowed". Aggregate once, filter after —
-- it reads better and it behaves the same on every warehouse.
--
-- Tolerance is 0.01. The last month absorbs the remainder, so a fully covered
-- policy closes EXACTLY. Anything above a cent is a real allocation bug.
-- ============================================================================

with per_policy as (
    select
        policy_key,
        any_value(written_premium) as written_premium,
        any_value(term_days)       as term_days,
        sum(earned_premium)        as total_earned,
        sum(days_on_risk)          as total_days
    from {{ ref('fct_policy_month') }}
    group by policy_key
)

select
    policy_key,
    written_premium,
    total_earned,
    total_earned - written_premium as variance,
    total_days,
    term_days
from per_policy
-- only policies whose full term sits inside the generated month window; a policy
-- half outside it has legitimately earned less than it wrote
where total_days = term_days
  and abs(total_earned - written_premium) > 0.01
