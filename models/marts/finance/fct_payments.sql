{#-
  One row per payment attempt (charge, failed attempt or refund) with the
  invoice it was applied to. Amounts keep their sign so summing succeeded
  rows gives net cash collected.
-#}

with payments as (

    select * from {{ ref('stg_payments') }}

),

invoices as (

    select
        invoice_id,
        invoice_number,
        subscription_id,
        plan_id,
        plan_tier,
        issued_date,
        due_date,
        total_amount as invoice_total_amount

    from {{ ref('fct_invoices') }}

),

joined as (

    select
        payments.payment_id,
        payments.invoice_id,
        invoices.invoice_number,
        payments.customer_id,
        invoices.subscription_id,
        invoices.plan_id,
        invoices.plan_tier,
        payments.payment_status,
        payments.payment_type,
        payments.payment_method,
        payments.failure_reason,
        payments.currency,
        payments.amount,
        case when payments.payment_status = 'succeeded' then payments.amount else 0 end as settled_amount,
        payments.paid_at,
        payments.paid_date,
        date_trunc('month', payments.paid_date) as paid_month,
        invoices.issued_date as invoice_issued_date,
        invoices.due_date as invoice_due_date,
        invoices.invoice_total_amount,
        date_diff('day', invoices.issued_date, payments.paid_date) as days_after_issue,
        payments.paid_date > invoices.due_date as is_late

    from payments
    inner join invoices
        on payments.invoice_id = invoices.invoice_id

)

select * from joined
