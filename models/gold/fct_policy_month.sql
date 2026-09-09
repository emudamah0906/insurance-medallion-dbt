-- GOLD — the model that finally answers the business question.
--
-- GRAIN: one row per policy version per month of its term.
--
-- Everything before this described what happened. This one measures whether the
-- business is working, by putting premium and claims in the same period so a
-- loss ratio can be computed.
--
-- ---------------------------------------------------------------------------
-- WRITTEN vs EARNED PREMIUM — the insurance concept that matters here.
--
-- A 12-month policy sold on 1 March for $1,200 does not earn $1,200 in March. It
-- earns it across the term, roughly $100 a month, because the insurer is only on
-- risk for the days that have passed. Premium you have BOOKED is *written*;
-- premium you have actually EARNED by carrying risk is *earned*.
--
-- Compare a month's claims against written premium and every month a policy is
-- sold looks wildly profitable, and every month after looks like a disaster.
-- Loss ratio only means anything against EARNED premium.
--
-- Terms here are exactly 365 days, so earning is straight-line pro-rata by day.
-- ---------------------------------------------------------------------------
--
-- Which VERSION's premium? The one in force at the start of the month. That is the
-- point-in-time join again — a month in 2024 earns the premium that was in force in
-- 2024, not the one someone set in August 2026.

with months as (
    select month_start
    from unnest(generate_date_array('2024-01-01', '2027-12-01', interval 1 month)) as month_start
),

policy_versions as (
    select *
    from {{ ref('dim_policy') }}
    where start_date is not null
      and end_date  is not null
      and end_date >= start_date
),

-- a policy-month exists where the month overlaps the policy term AND that version
-- was the one in force at the start of the month
policy_months as (
    select
        p.policy_key,
        p.policy_natural_key,
        p.broker_key,
        p.product,
        p.status,
        p.premium,
        p.start_date,
        p.end_date,
        m.month_start,
        date_add(m.month_start, interval 1 month)      as next_month_start,
        -- term is inclusive of end_date, so add a day to make the arithmetic half-open
        date_add(p.end_date, interval 1 day)           as term_end_excl
    from months m
    join policy_versions p
      on m.month_start  <= p.end_date
     and date_add(m.month_start, interval 1 month) > p.start_date
     and m.month_start between p.valid_from and p.valid_to
),

earned as (
    select
        *,
        date_diff(term_end_excl, start_date, day) as term_days,
        date_diff(
            least(next_month_start, term_end_excl),
            greatest(month_start, start_date),
            day
        ) as days_on_risk
    from policy_months
),

claims_by_policy_month as (
    select
        policy_natural_key,
        date_trunc(claim_date, month) as month_start,
        count(*)                      as claim_count,
        sum(amount)                   as claim_amount
    from {{ ref('fct_claim') }}
    where claim_date is not null
    group by 1, 2
),

-- ---------------------------------------------------------------------------
-- ALLOCATING A TOTAL ACROSS PERIODS — two things to get right.
--
-- 1. NUMERIC, NOT FLOAT. The first version used safe_divide(), which takes two
--    INT64s and returns a FLOAT64. Multiplying NUMERIC premium by that coerced the
--    whole calculation into binary floating point, and the variances came back as
--    0.05000000000006821. Floating point cannot represent 0.01 exactly. Money is
--    computed in exact decimal, always.
--
-- 2. THE LAST PERIOD ABSORBS THE REMAINDER. Rounding each month to cents means the
--    months do not add back to the written premium — 13 roundings of half a cent
--    drift a few cents apart. So every month except the last takes its rounded
--    pro-rata share, and the final month takes whatever is left. The parts then sum
--    to the whole, exactly, which is how financial allocation actually works.
--
--    Only applied where the policy's whole term sits inside the month window. A
--    policy running past the window has legitimately earned less than it wrote, and
--    forcing it to close would invent premium.
-- ---------------------------------------------------------------------------

with_position as (
    select
        e.*,
        row_number() over (partition by e.policy_key order by e.month_start) as month_rn,
        count(*)    over (partition by e.policy_key)                          as month_count,
        sum(e.days_on_risk) over (partition by e.policy_key)                  as days_covered,
        round(
            cast(e.premium as numeric)
              * cast(e.days_on_risk as numeric)
              / nullif(cast(e.term_days as numeric), 0),
            2
        ) as pro_rata_earned
    from earned e
),

allocated as (
    select
        *,
        -- everything earned in the months BEFORE this one
        coalesce(
            sum(pro_rata_earned) over (
                partition by policy_key
                order by month_start
                rows between unbounded preceding and 1 preceding
            ),
            0
        ) as earned_so_far
    from with_position
)

select
    a.policy_key,
    a.policy_natural_key,
    a.broker_key,
    a.product,
    a.status,
    a.month_start,
    a.premium                          as written_premium,
    a.days_on_risk,
    a.term_days,
    case
        when a.month_rn = a.month_count and a.days_covered = a.term_days
            then cast(a.premium as numeric) - a.earned_so_far   -- last month closes it out
        else a.pro_rata_earned
    end                                as earned_premium,
    coalesce(c.claim_count, 0)         as claim_count,
    coalesce(c.claim_amount, 0)        as incurred_claims
from allocated a
left join claims_by_policy_month c
       on a.policy_natural_key = c.policy_natural_key
      and a.month_start        = c.month_start
