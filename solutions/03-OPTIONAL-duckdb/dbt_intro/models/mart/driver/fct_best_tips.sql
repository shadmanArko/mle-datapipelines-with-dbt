{{ config(materialized='table', schema='driver') }}

with avg_tip as (
    select
        avg_tip_amount
    from {{ ref('int_avg_tips') }}
)

select
    payment_type,
    avg_tip_amount,
    case
        when avg_tip_amount < (select avg_tip_amount from avg_tip) then 'bad tip'
        when avg_tip_amount > (select avg_tip_amount from avg_tip) then 'good tip'
        else 'average tip'
    end as tip_status
from {{ ref('int_avg_tips_per_payment_type') }}
