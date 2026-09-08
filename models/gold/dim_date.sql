-- GOLD — date dimension, built from observed dates so the project stays free of
-- package dependencies. A real one would use a generated spine: with this approach a
-- date on which nothing happened simply doesn't exist, which bites the first time
-- someone asks about a gap in activity.
with all_dates as (
    select claim_date as d from {{ ref('silver_claims') }} where claim_date is not null
    union distinct
    select start_date from {{ ref('silver_policies') }} where start_date is not null
    union distinct
    select valid_from from {{ ref('silver_policies') }}
)
select
    d                       as date_day,
    extract(year    from d) as year_num,
    extract(quarter from d) as quarter_num,
    extract(month   from d) as month_num,
    format_date('%Y-%m', d) as year_month
from all_dates
