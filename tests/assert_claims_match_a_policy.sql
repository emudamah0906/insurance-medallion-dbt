-- ============================================================================
-- MATCH-RATE GATE.
--
-- Why this exists: the reconciliation gate compares row counts and total amount
-- between Silver and Gold. It passed while every one of the 12,000 claims failed to
-- join to a policy — a LEFT JOIN that matches nothing preserves both numbers
-- perfectly. A gate only guards what it actually measures.
--
-- WHY THERE IS A THRESHOLD RATHER THAN ZERO.
--
-- The source contains 129 deliberate orphan policy_ids drawn from a 900,000+ block;
-- real policies only reach POL005000. 128 of them survive dedupe. Those claims will
-- never match a policy version, on any build, forever.
--
-- A gate set to zero on a condition that is permanently non-zero fails every build,
-- and a check that always fails is a check the team turns off. So the threshold
-- encodes the KNOWN-GOOD state: 128 is expected, 129 is new and worth waking up for.
--
-- If this fires, something changed upstream — new orphan ids, or a join that broke.
-- ============================================================================

{% set expected_orphans = 128 %}

with stats as (
    select
        count(*)                                      as total_claims,
        countif(is_unmatched)                         as unmatched_total,
        countif(is_unmatched and claim_date_is_valid) as unmatched_with_good_date,
        countif(is_unmatched and not claim_date_is_valid) as unmatched_no_date
    from {{ ref('fct_claim') }}
)

select
    *,
    unmatched_with_good_date - {{ expected_orphans }} as above_expected
from stats
where unmatched_with_good_date > {{ expected_orphans }}
