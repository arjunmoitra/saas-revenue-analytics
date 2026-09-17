{#-
  Monthly revenue at the grain of customer x plan x month, combining three
  views of revenue that are often confused:

    recognized_revenue   earned in the month (service delivered), from the
                         simplified revenue-recognition model
    billed_amount        invoiced in the month (ex-tax, non-void), which for
                         annual plans lands in one month
    mrr                  contracted recurring run-rate at month end

  Months are limited to the reporting window (int_months). The plan on a
  one-time fee is the plan of the subscription the invoice belongs to.
-#}

with months as (

    select * from {{ ref('int_months') }}

),

recognized as (

    select
        customer_id,
        plan_id,
        revenue_month as month_start_date,
        sum(recognized_revenue) as recognized_revenue,
        sum(case when line_type = 'subscription' then recognized_revenue else 0 end) as recognized_recurring_revenue,
        sum(case when line_type = 'one_time' then recognized_revenue else 0 end) as recognized_one_time_revenue,
        sum(case when line_type = 'discount' then recognized_revenue else 0 end) as recognized_discount_amount

    from {{ ref('int_revenue_recognition') }}
    group by customer_id, plan_id, revenue_month

),

billed as (

    select
        customer_id,
        plan_id,
        issued_month as month_start_date,
        count(*) as invoice_count,
        sum(subtotal_amount) as billed_amount,
        sum(net_amount_collected) as collected_amount

    from {{ ref('fct_invoices') }}
    where invoice_status <> 'void'
    group by customer_id, plan_id, issued_month

),

mrr as (

    select
        customer_id,
        plan_id,
        month_start_date,
        sum(mrr_amount) as mrr,
        sum(quantity) as seats

    from {{ ref('int_subscription_mrr_monthly') }}
    group by customer_id, plan_id, month_start_date

),

keys as (

    select customer_id, plan_id, month_start_date from recognized
    union
    select customer_id, plan_id, month_start_date from billed
    union
    select customer_id, plan_id, month_start_date from mrr

),

joined as (

    select
        keys.customer_id,
        keys.plan_id,
        keys.month_start_date,
        coalesce(recognized.recognized_revenue, 0) as recognized_revenue,
        coalesce(recognized.recognized_recurring_revenue, 0) as recognized_recurring_revenue,
        coalesce(recognized.recognized_one_time_revenue, 0) as recognized_one_time_revenue,
        coalesce(recognized.recognized_discount_amount, 0) as recognized_discount_amount,
        coalesce(billed.invoice_count, 0) as invoice_count,
        coalesce(billed.billed_amount, 0) as billed_amount,
        coalesce(billed.collected_amount, 0) as collected_amount,
        coalesce(mrr.mrr, 0) as mrr,
        coalesce(mrr.mrr, 0) * 12 as arr,
        coalesce(mrr.seats, 0) as seats

    from keys
    inner join months
        on keys.month_start_date = months.month_start_date
    left join recognized
        on keys.customer_id = recognized.customer_id
        and keys.plan_id = recognized.plan_id
        and keys.month_start_date = recognized.month_start_date
    left join billed
        on keys.customer_id = billed.customer_id
        and keys.plan_id = billed.plan_id
        and keys.month_start_date = billed.month_start_date
    left join mrr
        on keys.customer_id = mrr.customer_id
        and keys.plan_id = mrr.plan_id
        and keys.month_start_date = mrr.month_start_date

)

select
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'plan_id', 'month_start_date']) }} as revenue_key,
    *

from joined
