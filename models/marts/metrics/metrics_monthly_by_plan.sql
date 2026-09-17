{#-
  One row per plan tier per month: MRR, customers, seats and recognised
  revenue by tier, plus counts of customers moving into and out of the tier.
  Plan-level metrics use the tier a customer is on at month end.
-#}

with months as (

    select * from {{ ref('int_months') }}

),

tiers as (

    select distinct
        plan_tier,
        plan_tier_rank

    from {{ ref('dim_plans') }}

),

mrr_by_tier as (

    select
        month_start_date,
        plan_tier,
        sum(mrr) as mrr,
        count(case when is_active then 1 end) as active_customers,
        sum(seats) as active_seats,
        count(case when mrr_movement_type = 'new' then 1 end) as new_customers,
        sum(new_mrr) as new_mrr,
        sum(expansion_mrr) as expansion_mrr,
        sum(contraction_mrr) as contraction_mrr,
        count(case when billing_interval = 'annual' then 1 end) as annual_customers

    from {{ ref('fct_mrr_movements') }}
    where is_active
    group by month_start_date, plan_tier

),

-- Churned MRR has no plan at month end, so attribute it to the tier the
-- customer was on in the prior month.
churn_by_prior_tier as (

    select
        month_start_date,
        lag(plan_tier) over (partition by customer_id order by month_start_date) as plan_tier,
        churned_mrr,
        case when mrr_movement_type = 'churn' then 1 else 0 end as is_churn

    from {{ ref('fct_mrr_movements') }}
    qualify mrr_movement_type = 'churn'

),

churn_agg as (

    select
        month_start_date,
        plan_tier,
        sum(churned_mrr) as churned_mrr,
        sum(is_churn) as churned_customers

    from churn_by_prior_tier
    group by month_start_date, plan_tier

),

plan_changes as (

    select
        date_trunc('month', start_date) as month_start_date,
        plan_tier,
        count(case when change_type = 'upgrade' then 1 end) as upgrades_into_tier,
        count(case when change_type = 'downgrade' then 1 end) as downgrades_into_tier

    from {{ ref('dim_subscriptions') }}
    where not is_trial
    group by date_trunc('month', start_date), plan_tier

),

revenue_by_tier as (

    select
        fct_revenue.month_start_date,
        dim_plans.plan_tier,
        sum(fct_revenue.recognized_revenue) as recognized_revenue,
        sum(fct_revenue.billed_amount) as billed_amount

    from {{ ref('fct_revenue') }}
    inner join {{ ref('dim_plans') }}
        on fct_revenue.plan_id = dim_plans.plan_id
    group by fct_revenue.month_start_date, dim_plans.plan_tier

),

joined as (

    select
        months.month_start_date,
        tiers.plan_tier,
        tiers.plan_tier_rank,
        coalesce(mrr_by_tier.mrr, 0) as mrr,
        coalesce(mrr_by_tier.mrr, 0) * 12 as arr,
        coalesce(mrr_by_tier.active_customers, 0) as active_customers,
        coalesce(mrr_by_tier.annual_customers, 0) as annual_customers,
        coalesce(mrr_by_tier.active_seats, 0) as active_seats,
        coalesce(mrr_by_tier.new_customers, 0) as new_customers,
        coalesce(mrr_by_tier.new_mrr, 0) as new_mrr,
        coalesce(mrr_by_tier.expansion_mrr, 0) as expansion_mrr,
        coalesce(mrr_by_tier.contraction_mrr, 0) as contraction_mrr,
        coalesce(churn_agg.churned_mrr, 0) as churned_mrr,
        coalesce(churn_agg.churned_customers, 0) as churned_customers,
        coalesce(plan_changes.upgrades_into_tier, 0) as upgrades_into_tier,
        coalesce(plan_changes.downgrades_into_tier, 0) as downgrades_into_tier,
        coalesce(revenue_by_tier.recognized_revenue, 0) as recognized_revenue,
        coalesce(revenue_by_tier.billed_amount, 0) as billed_amount,
        case when mrr_by_tier.active_customers > 0 then mrr_by_tier.mrr / mrr_by_tier.active_customers end as arpu

    from months
    cross join tiers
    left join mrr_by_tier
        on months.month_start_date = mrr_by_tier.month_start_date
        and tiers.plan_tier = mrr_by_tier.plan_tier
    left join churn_agg
        on months.month_start_date = churn_agg.month_start_date
        and tiers.plan_tier = churn_agg.plan_tier
    left join plan_changes
        on months.month_start_date = plan_changes.month_start_date
        and tiers.plan_tier = plan_changes.plan_tier
    left join revenue_by_tier
        on months.month_start_date = revenue_by_tier.month_start_date
        and tiers.plan_tier = revenue_by_tier.plan_tier

)

select
    {{ dbt_utils.generate_surrogate_key(['month_start_date', 'plan_tier']) }} as plan_month_key,
    *

from joined
