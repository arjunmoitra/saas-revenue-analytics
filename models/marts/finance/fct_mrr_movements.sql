{#-
  One row per customer per month from their first paid month onward, with
  month-end MRR and the movement versus the prior month. This is the table
  behind the MRR waterfall and retention analysis.
-#}

with movements as (

    select * from {{ ref('int_customer_mrr_monthly') }}

),

customers as (

    select
        customer_id,
        segment,
        country_code,
        industry,
        acquisition_channel

    from {{ ref('dim_customers') }}

),

-- Plan the customer is on at month end (at most one paid version is active on
-- any given day, so this is a clean lookup rather than an aggregation).
active_plan as (

    select
        customer_id,
        month_start_date,
        plan_id,
        plan_tier,
        billing_interval

    from {{ ref('int_subscription_mrr_monthly') }}
    qualify row_number() over (partition by customer_id, month_start_date order by mrr_amount desc) = 1

),

joined as (

    select
        movements.customer_id,
        movements.month_start_date,
        movements.month_end_date,
        customers.segment,
        customers.country_code,
        customers.industry,
        customers.acquisition_channel,
        active_plan.plan_id,
        active_plan.plan_tier,
        active_plan.billing_interval,
        movements.first_mrr_month,
        date_diff('month', movements.first_mrr_month, movements.month_start_date) as months_since_first_paid,
        movements.is_active,
        movements.active_subscription_count,
        movements.seats,
        movements.prior_mrr,
        movements.mrr,
        movements.mrr * 12 as arr,
        movements.mrr_movement_type,
        movements.new_mrr,
        movements.expansion_mrr,
        movements.contraction_mrr,
        movements.churned_mrr,
        movements.reactivation_mrr,
        movements.mrr - movements.prior_mrr as net_mrr_change

    from movements
    left join customers
        on movements.customer_id = customers.customer_id
    left join active_plan
        on movements.customer_id = active_plan.customer_id
        and movements.month_start_date = active_plan.month_start_date

)

select
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'month_start_date']) }} as mrr_movement_key,
    *

from joined
