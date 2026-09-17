{#-
  One row per invoice with its line items rolled up by type. Used to
  reconcile invoice headers against their lines and to split billed amounts
  into recurring, one-time and discount components.
-#}

with line_items as (

    select * from {{ ref('stg_invoice_line_items') }}

),

totals as (

    select
        invoice_id,
        count(*) as line_item_count,
        sum(amount) as line_items_subtotal,
        sum(case when line_type = 'subscription' then amount else 0 end) as subscription_amount,
        sum(case when line_type = 'one_time' then amount else 0 end) as one_time_amount,
        sum(case when line_type = 'discount' then amount else 0 end) as discount_amount,
        min(service_period_start) as earliest_service_period_start,
        max(service_period_end) as latest_service_period_end

    from line_items
    group by invoice_id

)

select * from totals
