with source as (

    select * from {{ source('billing', 'raw_invoices') }}

),

renamed as (

    select
        invoice_id,
        invoice_number,
        customer_id,
        subscription_id,
        lower(trim(status)) as invoice_status,
        upper(currency) as currency,
        {{ cents_to_dollars('subtotal_cents') }} as subtotal_amount,
        {{ cents_to_dollars('tax_cents') }} as tax_amount,
        {{ cents_to_dollars('total_cents') }} as total_amount,
        cast(issued_at as timestamp) as issued_at,
        cast(issued_at as date) as issued_date,
        cast(due_at as date) as due_date,
        cast(service_period_start as date) as service_period_start,
        cast(service_period_end as date) as service_period_end

    from source

)

select * from renamed
