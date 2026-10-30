{{ config(materialized='table', schema='int') }}

with avg_tips as (
    select
        payment_type,
        avg(tip_amount) as avg_tip_amount
    from {{ ref('stg_yellow_taxi') }}
    where payment_type between 1 and 6
    group by 1
),
payment_type_lookup as (
    select
        id as payment_type_id,
        payment_type
    from {{ ref('payment_type') }}
)

select
    payment_type_lookup.payment_type,
    avg_tips.avg_tip_amount
from avg_tips
join payment_type_lookup
    on payment_type_lookup.payment_type_id = avg_tips.payment_type
