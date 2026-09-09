-- ============================================================================
-- SOURCE CONTROL TOTAL — the strongest check in the project.
--
-- Every other gate compares one layer against another. That catches a broken join,
-- but it cannot catch a bad LOAD. If Bronze only ever received half the file, Silver
-- and Gold agree with each other perfectly and every other gate goes green while the
-- warehouse quietly reports half a business.
--
-- This anchors to totals that arrive WITH the data, as `_control_totals.csv`. That is
-- how real batch interfaces work: the source system sends a trailer record carrying
-- row count and a hash total, and the loader proves it received all of it.
--
-- WHY NOT A NUMBER IN A DOCUMENT.
--
-- The first version of this test hardcoded $1,063,516,068.75, taken from the project's
-- own GENERATOR.md. The file actually contains $1,063,624,699.09 — the data had been
-- regenerated and the document had not. The gate failed against a wrong expectation
-- and skipped 13 downstream models.
--
-- A control total maintained by hand drifts away from the data it describes. Making it
-- data means it cannot.
--
-- THIS IS THE CHECK THAT CATCHES A SILENT PARTIAL LOAD — the same idea as reconciling
-- record counts against the source system at Caplin Point in 2018, and the control
-- totals blocking layer promotion at Tokio Marine now.
-- ============================================================================

with expected as (
    select
        source_file,
        cast(row_count  as int64)   as expected_rows,
        cast(hash_total as numeric) as expected_total
    from {{ ref('_control_totals') }}
    where source_file = 'claims'
),

actual as (
    select
        count(*)                          as actual_rows,
        sum(safe_cast(amount as numeric)) as actual_total
    from {{ ref('bronze_claims') }}
)

select
    e.expected_rows,
    a.actual_rows,
    a.actual_rows - e.expected_rows        as row_variance,
    e.expected_total,
    a.actual_total,
    a.actual_total - e.expected_total      as amount_variance
from expected e
cross join actual a
where a.actual_rows != e.expected_rows
   or abs(a.actual_total - e.expected_total) > 0.01
