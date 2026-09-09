-- SILVER — policies, as SCD Type 2. The centrepiece of this project.
--
-- WHAT WE HAVE: two full extracts of the same 5,000 policies, taken 2026-08-01 and
-- 2026-08-15. 602 of them changed in between (premium, status, or both).
--
-- WHAT SCD2 GIVES US: instead of one row per policy showing today's values, one row
-- per policy PER VERSION, each stamped with the window it was true for. A claim from
-- 5 August then joins to the premium that was actually in force on 5 August, not the
-- one in force today. Without this, restating history is impossible.
--
-- EXPECTED OUTPUT: 5,000 policies + 602 second versions = 5,602 rows.
-- 5,000 of them is_current = true.
--
-- First version valid_from is floored to 1900-01-01 so claims predating the first
-- extract still join. See the note on the select below.
--
-- WHY A HASH: comparing four columns with OR-ed inequality checks breaks the moment
-- one is NULL (NULL != NULL is not true). Hashing the whole tuple sidesteps that and
-- scales to any number of tracked columns. This is the same idea Data Vault calls a
-- hashdiff.

with bronze as (select * from {{ ref('bronze_policies') }}),

typed as (
    select
        policy_id,
        broker_id,
        -- upper AND trim. The source sends 5 products in 20 spellings:
        -- 'Property', 'PROPERTY', 'property', '  Property '. Trimming alone leaves
        -- three of them, so every report groups the same product into three rows.
        -- Conforming means case and whitespace — doing one and forgetting the other
        -- is the classic version of this bug, and it hides until someone sums a chart.
        upper(trim(product))         as product,
        safe_cast(premium as numeric) as premium,
        upper(trim(status))          as status,
        coalesce(
            safe_cast(start_date as date),
            safe.parse_date('%d/%m/%Y', start_date)
        ) as start_date,
        coalesce(
            safe_cast(end_date as date),
            safe.parse_date('%d/%m/%Y', end_date)
        ) as end_date,
        cast(extract_date as date)   as extract_date
    from bronze
    -- 25 duplicate policy_ids inside each extract. Dedupe WITHIN the extract, never
    -- across it — across is the history we came for.
    qualify row_number() over (partition by policy_id, extract_date order by _source_file) = 1
),

hashed as (
    select
        *,
        to_hex(md5(concat(
            coalesce(broker_id, ''), '|',
            coalesce(product, ''), '|',
            coalesce(cast(premium as string), ''), '|',
            coalesce(status, '')
        ))) as _attribute_hash
    from typed
),

with_previous as (
    select
        *,
        lag(_attribute_hash) over (partition by policy_id order by extract_date) as _prev_hash
    from hashed
),

-- Keep only the extracts where something actually changed. An unchanged policy
-- contributes one row, not two — that is the entire point of SCD2 versus just
-- keeping every snapshot forever.
change_points as (
    select *
    from with_previous
    where _prev_hash is null or _prev_hash != _attribute_hash
),

versioned as (
    select
        *,
        extract_date as valid_from,
        lead(extract_date) over (partition by policy_id order by extract_date) as _next_version_from
    from change_points
)

select
    policy_id,
    broker_id,
    product,
    premium,
    status,
    start_date,
    end_date,
    -- THE FLOOR DATE, and it matters more than it looks.
    --
    -- The first version of a policy must be valid from the BEGINNING OF TIME, not
    -- from the date we happened to take our first extract. Our first extract is
    -- 2026-08-01; the claims go back to 2024. Stamp valid_from as the extract date
    -- and every claim older than the snapshot falls outside every window and matches
    -- nothing — silently, because a LEFT JOIN just returns nulls.
    --
    -- A dimension can only serve history that starts after you began collecting it
    -- unless you do this.
    case
        when _prev_hash is null then date '1900-01-01'
        else valid_from
    end as valid_from,
    -- valid_to is the day BEFORE the next version starts, so the windows don't overlap.
    -- Overlapping windows are the classic SCD2 bug: a point-in-time join matches two
    -- rows and every measure silently doubles.
    coalesce(date_sub(_next_version_from, interval 1 day), date '9999-12-31') as valid_to,
    _next_version_from is null as is_current,
    _attribute_hash
from versioned
