-- BRONZE — brokers. 51 rows, 50 distinct (BRK0008 appears twice).
select
    cast(broker_id   as string) as broker_id,
    cast(broker_name as string) as broker_name,
    cast(region      as string) as region,
    cast(email       as string) as email,
    'brokers'                   as _source_file,
    current_timestamp()         as _loaded_at
from {{ ref('brokers') }}
