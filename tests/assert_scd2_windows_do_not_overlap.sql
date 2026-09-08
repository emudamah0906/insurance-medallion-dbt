-- ============================================================================
-- THE SCD2 CORRECTNESS GATE.
--
-- The classic SCD2 bug is overlapping validity windows. If version 1 of a policy is
-- valid to 15 Aug and version 2 is valid FROM 15 Aug, then a claim dated 15 Aug
-- matches BOTH — and every measure joined through it silently doubles.
--
-- It is invisible in row counts, invisible in tests on the dimension itself, and it
-- corrupts every historical report. So it gets its own gate.
--
-- Returns any policy where one version's window starts on or before the previous
-- version's window ends.
-- ============================================================================

with windows as (
    select
        policy_natural_key,
        valid_from,
        valid_to,
        lead(valid_from) over (
            partition by policy_natural_key order by valid_from
        ) as next_valid_from
    from {{ ref('dim_policy') }}
)

select
    policy_natural_key,
    valid_from,
    valid_to,
    next_valid_from
from windows
where next_valid_from is not null
  and next_valid_from <= valid_to
