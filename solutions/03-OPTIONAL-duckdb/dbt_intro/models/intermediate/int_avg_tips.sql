{{ config(materialized='table', schema='int') }}

select
    avg(tip_amount) as avg_tip_amount
from {{ ref('stg_yellow_taxi') }}
where payment_type between 1 and 6
