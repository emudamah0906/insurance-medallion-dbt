-- ============================================================================
-- THE GATE THAT WAS MISSING.
--
-- The reconciliation gate compares row counts and amounts between Silver and Gold.
-- It passed while every single claim failed to join to a policy — because a LEFT JOIN
-- that matches nothing preserves the row count and the sum perfectly.
--
-- That is the lesson: a gate only guards what it actually measures. Counting rows
-- proves you did not LOSE anything. It says nothing about whether the join WORKED.
--
-- So this one measures the thing that broke: the match rate.
--
-- Claims with an unusable claim_date genuinely cannot be placed in time, and there
-- are 204 of those. Everything else must find its policy version. Threshold is set
-- just above that, so a real regression trips it immediately.
-- ============================================================================

with stats as (
    select
        count(*)                                                        as total_claims,
        countif(is_unmatched)                                           as unmatched,
        countif(is_unmatched and claim_date_is_valid)                   as unmatched_with_good_date
    from {{ ref('fct_claim') }}
)

select *
from stats
-- a claim with a valid date has no excuse for not matching a policy version
where unmatched_with_good_date > 0
