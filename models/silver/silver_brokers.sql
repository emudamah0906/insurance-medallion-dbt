-- SILVER — brokers. 51 rows in, 50 out. BRK0008 appears twice as an exact copy.
select
    broker_id,
    trim(broker_name)  as broker_name,
    upper(trim(region)) as region,
    lower(trim(email))  as email,
    _loaded_at
from {{ ref('bronze_brokers') }}
qualify row_number() over (partition by broker_id order by _loaded_at) = 1
