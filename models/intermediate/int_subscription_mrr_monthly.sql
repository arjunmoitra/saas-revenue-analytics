{#-
  One row per subscription version per month in which it was active on the
  last day of the month. MRR is a point-in-time measure taken at month end, so
  a subscription that started on the 20th counts fully for that month and one
  that was cancelled effective the 15th does not count at all.
-#}

with months as (

    select * from {{ ref('int_months') }}

),

periods as (

    select * from {{ ref('int_subscription_periods') }}

),

active_at_month_end as (

    select
        months.month_start_date,
        months.month_end_date,
        periods.subscription_id,
        periods.customer_id,
        periods.plan_id,
        periods.plan_tier,
        periods.billing_interval,
        periods.quantity,
        periods.mrr_amount

    from periods
    inner join months
        on periods.start_date <= months.month_end_date
        and periods.effective_end_date >= months.month_end_date

)

select * from active_at_month_end
