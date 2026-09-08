-- BRONZE — policies.
--
-- THE RULE FOR THIS WHOLE LAYER: Bronze does not cast, clean, filter or dedupe.
-- Everything stays as the source sent it. The only things added are metadata columns
-- prefixed with an underscore, so they can never collide with a source column name.
--
-- Two extracts of the same source table, stacked. union all, not union — union
-- deduplicates, and these two files contain the same 5,025 policy ids on purpose.
-- extract_date is what makes SCD2 possible in Silver; lose it here and the history
-- is gone for good.
--
-- Dates stay strings. 73 start_dates and 69 end_dates per extract are unparseable
-- ('N/A', '31/12/2025', empty). Casting here would either crash the build or silently
-- null them — Silver decides what to do, on the record.

with snapshot_01 as (select *, 'policies_snapshot_01' as _source_file from {{ ref('policies_snapshot_01') }}),
     snapshot_02 as (select *, 'policies_snapshot_02' as _source_file from {{ ref('policies_snapshot_02') }})

select
    cast(policy_id    as string) as policy_id,
    cast(broker_id    as string) as broker_id,
    cast(product      as string) as product,
    cast(start_date   as string) as start_date,
    cast(end_date     as string) as end_date,
    cast(premium      as string) as premium,
    cast(status       as string) as status,
    cast(extract_date as string) as extract_date,
    _source_file                 as _source_file,
    current_timestamp()          as _loaded_at
from (
    select * from snapshot_01
    union all
    select * from snapshot_02
)
