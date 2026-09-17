{#-
  Simplified revenue recognition: one row per invoice line item per calendar
  month in which service is delivered.

  Assumptions (portfolio simplification, not GAAP/ASC 606 advice):
    * Revenue is earned evenly over the line's service period, allocated by
      the number of service days that fall in each month. An annual invoice
      therefore recognises roughly 1/12 per month; a one-time fee has a
      single-day service period and is recognised entirely in that month.
    * Voided invoices are excluded. Uncollectible invoices are still
      recognised as revenue (bad debt would be an expense, not a revenue
      reversal) and can be filtered via invoice_status.
    * Tax is not revenue and is not allocated.
    * Rounding: each month's amount is the difference between cumulative
      rounded shares, so the monthly amounts always sum exactly to the line
      amount. This is what makes the reconciliation test exact.
    * Months beyond the snapshot date are kept so deferred revenue can be
      computed; downstream monthly models filter to the reporting window.
-#}

with line_items as (

    select * from {{ ref('stg_invoice_line_items') }}

),

invoices as (

    select * from {{ ref('stg_invoices') }}
    where invoice_status <> 'void'

),

subscriptions as (

    select
        subscription_id,
        plan_id

    from {{ ref('stg_subscriptions') }}

),

lines as (

    select
        line_items.line_item_id,
        line_items.invoice_id,
        invoices.customer_id,
        invoices.subscription_id,
        -- One-time fees carry no plan; attribute them to the plan of the
        -- subscription the invoice was raised for.
        coalesce(line_items.plan_id, subscriptions.plan_id) as plan_id,
        line_items.line_type,
        invoices.invoice_status,
        invoices.issued_date,
        line_items.amount,
        line_items.service_period_start,
        line_items.service_period_end,
        date_diff('day', line_items.service_period_start, line_items.service_period_end) + 1 as service_days

    from line_items
    inner join invoices
        on line_items.invoice_id = invoices.invoice_id
    left join subscriptions
        on invoices.subscription_id = subscriptions.subscription_id

),

service_months as (

    -- Every calendar month touched by any service period, generated from the
    -- overall min/max so multi-year annual lines are covered.
    select
        cast(month_start as date) as month_start_date,
        cast(month_start + interval 1 month - interval 1 day as date) as month_end_date

    from (
        select unnest(generate_series(
            date_trunc('month', (select min(service_period_start) from lines)),
            date_trunc('month', (select max(service_period_end) from lines)),
            interval 1 month
        )) as month_start
    )

),

allocated_days as (

    select
        lines.line_item_id,
        lines.invoice_id,
        lines.customer_id,
        lines.subscription_id,
        lines.plan_id,
        lines.line_type,
        lines.invoice_status,
        lines.issued_date,
        lines.amount,
        lines.service_days,
        service_months.month_start_date as revenue_month,
        date_diff(
            'day',
            greatest(lines.service_period_start, service_months.month_start_date),
            least(lines.service_period_end, service_months.month_end_date)
        ) + 1 as service_days_in_month

    from lines
    inner join service_months
        on lines.service_period_start <= service_months.month_end_date
        and lines.service_period_end >= service_months.month_start_date

),

cumulative as (

    select
        *,
        sum(service_days_in_month) over (
            partition by line_item_id
            order by revenue_month
            rows between unbounded preceding and current row
        ) as cumulative_service_days

    from allocated_days

),

recognized as (

    select
        line_item_id,
        invoice_id,
        customer_id,
        subscription_id,
        plan_id,
        line_type,
        invoice_status,
        issued_date,
        revenue_month,
        amount as line_amount,
        service_days,
        service_days_in_month,
        round(amount * cumulative_service_days / service_days, 2)
            - round(amount * (cumulative_service_days - service_days_in_month) / service_days, 2)
            as recognized_revenue

    from cumulative

)

select * from recognized
