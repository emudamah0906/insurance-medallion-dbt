-- GOLD — broker dimension. Type 1: we keep only the current values.
-- Brokers here have no meaningful history to preserve, so versioning them would be
-- ceremony without benefit. Choosing Type 1 deliberately is worth saying out loud —
-- SCD2 on everything is a common over-engineering mistake.
select
    to_hex(md5(broker_id)) as broker_key,   -- surrogate key
    broker_id              as broker_natural_key,
    broker_name,
    region,
    email
from {{ ref('silver_brokers') }}
