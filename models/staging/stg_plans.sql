with source as (

    select * from {{ source('billing', 'raw_plans') }}

),

renamed as (

    select
        plan_id,
        plan_name,
        lower(tier) as plan_tier,
        tier_rank as plan_tier_rank,
        lower(billing_interval) as billing_interval,
        {{ cents_to_dollars('unit_price_cents') }} as unit_price,
        upper(currency) as currency,
        lower(is_active) = 'true' as is_active,
        cast(created_at as timestamp) as created_at

    from source

)

select * from renamed
