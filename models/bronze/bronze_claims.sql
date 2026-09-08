-- BRONZE — claims. As sent.
--
-- 12,060 rows, 12,000 distinct claim_ids (60 deliberate duplicates).
-- 163 claim_dates are unparseable. 12 status spellings of 4 real statuses.
-- None of that is fixed here. Silver fixes it, and the tests report it.

select
    cast(claim_id   as string) as claim_id,
    cast(policy_id  as string) as policy_id,
    cast(claim_date as string) as claim_date,
    cast(amount     as string) as amount,
    cast(status     as string) as status,
    'claims'                   as _source_file,
    current_timestamp()        as _loaded_at
from {{ ref('claims') }}
