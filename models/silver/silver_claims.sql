-- SILVER — claims. Conformed, deduped, typed. This is where the mess gets dealt with,
-- on the record, with a flag for anything that couldn't be saved.
--
-- Three problems from Bronze, three decisions:
--
--   1. 60 duplicate claim_ids -> keep one. QUALIFY does it in one pass.
--   2. 259 unparseable claim_dates -> recover what we can, null the rest, FLAG BOTH.
--      53 of them are '31/12/2025' — that's DD/MM/YYYY, a real date in the wrong
--      format, and throwing it away would lose good data. The other ~206 are 'N/A',
--      empty, '0000-00-00' and '2026-13-45'. Those are not dates in any format.
--   3. 12 status spellings of 4 real values -> trim and upper.
--
-- Nulling a bad value silently is the failure mode here. claim_date_is_valid means
-- nobody downstream has to guess whether a null date is missing or was mangled.

with bronze as (select * from {{ ref('bronze_claims') }}),

deduped as (
    select *
    from bronze
    -- QUALIFY filters on a window function without a subquery. Keep the first row
    -- per claim_id; the duplicates here are exact copies, so which one wins is
    -- arbitrary — but it must be DETERMINISTIC, hence the order by.
    qualify row_number() over (partition by claim_id order by _loaded_at, policy_id) = 1
),

parsed as (
    select
        claim_id,
        policy_id,
        claim_date as claim_date_raw,
        -- try ISO first, then DD/MM/YYYY. safe_cast and safe.parse_date return NULL
        -- instead of erroring, which is the whole reason the build survives dirty data.
        coalesce(
            safe_cast(claim_date as date),
            safe.parse_date('%d/%m/%Y', claim_date)
        ) as claim_date,
        safe_cast(amount as numeric) as amount,
        upper(trim(status))          as status,
        _source_file,
        _loaded_at
    from deduped
)

select
    *,
    claim_date is not null as claim_date_is_valid
from parsed
