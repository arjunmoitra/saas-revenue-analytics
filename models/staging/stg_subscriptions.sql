with source as (

    select * from {{ source('billing', 'raw_subscriptions') }}

),

renamed as (

    select
        subscription_id,
        customer_id,
        plan_id,
        previous_subscription_id,
        quantity,
        lower(trim(status)) as subscription_status,
        lower(is_trial) = 'true' as is_trial,
        cast(start_date as date) as start_date,
        cast(end_date as date) as end_date,
        cast(canceled_at as timestamp) as canceled_at,
        nullif(trim(cancellation_reason), '') as cancellation_reason,
        cast(created_at as timestamp) as created_at,
        cast(updated_at as timestamp) as updated_at

    from source

)

select * from renamed
