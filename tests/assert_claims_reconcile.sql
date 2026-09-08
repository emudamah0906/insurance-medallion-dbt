-- ============================================================================
-- THE RECONCILIATION GATE — Silver to Gold.
--
-- A GATE, not a report. A report tells you tomorrow that yesterday was wrong.
-- A gate stops the wrong numbers reaching the layer people query: this test fails,
-- dbt marks the build failed, and nothing downstream of it runs.
--
-- What it guards: fct_claim joins to dim_policy. Joins are where warehouses quietly
-- start lying. Get the join wrong one way and you LOSE rows; get it wrong the other
-- way — an overlapping SCD2 window, say — and you DUPLICATE them. Both leave a table
-- that looks completely plausible.
--
-- So: row count and total claim amount must survive the trip from Silver to Gold,
-- exactly. Not approximately. If one claim goes missing out of twelve thousand, this
-- fails, and that is the point.
--
-- Amount tolerance is 0.01 for decimal rounding. Row count tolerance is zero.
-- ============================================================================

with silver as (
    select count(*) as n_rows, sum(amount) as total_amount
    from {{ ref('silver_claims') }}
),

gold as (
    select count(*) as n_rows, sum(amount) as total_amount
    from {{ ref('fct_claim') }}
),

comparison as (
    select
        s.n_rows           as silver_rows,
        g.n_rows           as gold_rows,
        g.n_rows - s.n_rows as row_variance,
        s.total_amount     as silver_amount,
        g.total_amount     as gold_amount,
        g.total_amount - s.total_amount as amount_variance
    from silver s cross join gold g
)

-- A dbt singular test fails when it RETURNS ROWS. So this returns nothing when
-- everything ties, and returns the variance when it doesn't.
select *
from comparison
where row_variance != 0
   or abs(amount_variance) > 0.01
