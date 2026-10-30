{{ config(materialized='table', schema='stg') }}

select
    "VendorID" as vendor_id,
    tpep_pickup_datetime as pickup_datetime,
    tpep_dropoff_datetime as dropoff_datetime,
    passenger_count,
    trip_distance,
    "RatecodeID" as rate_code_id,
    store_and_fwd_flag,
    "PULocationID" as pickup_location_id,
    "DOLocationID" as dropoff_location_id,
    payment_type,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    total_amount,
    congestion_surcharge,
    "Airport_fee" as airport_fee,
    cbd_congestion_fee
from {{ source('src_yellow_taxi', 'yellow_taxi') }}
