with source as (

    select * from {{ source('billing', 'raw_payments') }}

),

renamed as (

    select
        payment_id,
        invoice_id,
        customer_id,
        -- Refunds arrive as negative amounts; keep the sign so net cash is a plain sum.
        {{ cents_to_dollars('amount_cents') }} as amount,
        upper(currency) as currency,
        -- Source emits "succeeded", "SUCCEEDED" and "Succeeded" for the same state.
        lower(trim(status)) as payment_status,
        lower(trim(payment_type)) as payment_type,
        lower(trim(payment_method)) as payment_method,
        nullif(trim(failure_reason), '') as failure_reason,
        cast(paid_at as timestamp) as paid_at,
        cast(paid_at as date) as paid_date

    from source

)

select * from renamed
