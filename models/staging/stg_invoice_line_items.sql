with source as (

    select * from {{ source('billing', 'raw_invoice_line_items') }}

),

renamed as (

    select
        line_item_id,
        invoice_id,
        plan_id,
        lower(trim(line_type)) as line_type,
        description,
        quantity,
        {{ cents_to_dollars('unit_amount_cents') }} as unit_amount,
        {{ cents_to_dollars('amount_cents') }} as amount,
        cast(service_period_start as date) as service_period_start,
        cast(service_period_end as date) as service_period_end

    from source

)

select * from renamed
