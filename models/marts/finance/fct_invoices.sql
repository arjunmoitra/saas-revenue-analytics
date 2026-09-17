{#-
  One row per invoice with line-item breakdown, payment status and ageing.
  Voided invoices are kept (flagged via invoice_status) so the table
  reconciles to the source; revenue models exclude them.
-#}

with invoices as (

    select * from {{ ref('stg_invoices') }}

),

line_totals as (

    select * from {{ ref('int_invoice_line_totals') }}

),

payments as (

    select * from {{ ref('int_invoice_payments') }}

),

subscriptions as (

    select
        subscription_id,
        plan_id,
        plan_tier,
        billing_interval

    from {{ ref('dim_subscriptions') }}

),

joined as (

    select
        invoices.invoice_id,
        invoices.invoice_number,
        invoices.customer_id,
        invoices.subscription_id,
        subscriptions.plan_id,
        subscriptions.plan_tier,
        subscriptions.billing_interval,
        invoices.invoice_status,
        invoices.currency,
        invoices.issued_date,
        date_trunc('month', invoices.issued_date) as issued_month,
        invoices.due_date,
        invoices.service_period_start,
        invoices.service_period_end,
        date_diff('day', invoices.service_period_start, invoices.service_period_end) + 1 as service_days,
        invoices.subtotal_amount,
        invoices.tax_amount,
        invoices.total_amount,
        coalesce(line_totals.line_item_count, 0) as line_item_count,
        coalesce(line_totals.line_items_subtotal, 0) as line_items_subtotal,
        coalesce(line_totals.subscription_amount, 0) as subscription_amount,
        coalesce(line_totals.one_time_amount, 0) as one_time_amount,
        coalesce(line_totals.discount_amount, 0) as discount_amount,
        coalesce(payments.amount_charged, 0) as amount_charged,
        coalesce(payments.amount_refunded, 0) as amount_refunded,
        coalesce(payments.net_amount_collected, 0) as net_amount_collected,
        -- Outstanding amount still owed. Refunds do not re-open a balance and a
        -- voided invoice is never collectable.
        case
            when invoices.invoice_status = 'void' then 0
            else greatest(invoices.total_amount - coalesce(payments.amount_charged, 0), 0)
        end as balance_due,
        coalesce(payments.failed_attempt_count, 0) as failed_attempt_count,
        payments.first_payment_date,
        payments.last_payment_date,
        date_diff('day', invoices.issued_date, payments.first_payment_date) as days_to_first_payment,
        invoices.invoice_status = 'open'
            and invoices.due_date < cast('{{ var("as_of_date") }}' as date) as is_past_due,
        invoices.subtotal_amount = coalesce(line_totals.line_items_subtotal, 0) as is_reconciled_to_lines

    from invoices
    left join line_totals
        on invoices.invoice_id = line_totals.invoice_id
    left join payments
        on invoices.invoice_id = payments.invoice_id
    left join subscriptions
        on invoices.subscription_id = subscriptions.subscription_id

)

select * from joined
