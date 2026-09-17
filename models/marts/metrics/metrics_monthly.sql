{#-
  One row per month: the executive KPI set. Every metric here is derived from
  the marts, never from raw tables, and the definitions are documented in the
  accompanying schema.yml and README.
-#}

with months as (

    select * from {{ ref('int_months') }}

),

mrr_movements as (

    select
        month_start_date,
        sum(mrr) as mrr,
        sum(prior_mrr) as beginning_mrr,
        sum(new_mrr) as new_mrr,
        sum(expansion_mrr) as expansion_mrr,
        sum(reactivation_mrr) as reactivation_mrr,
        sum(contraction_mrr) as contraction_mrr,
        sum(churned_mrr) as churned_mrr,
        count(case when is_active then 1 end) as active_customers,
        count(case when mrr_movement_type = 'new' then 1 end) as new_customers,
        count(case when mrr_movement_type = 'churn' then 1 end) as churned_customers,
        count(case when mrr_movement_type = 'reactivation' then 1 end) as reactivated_customers,
        count(case when mrr_movement_type = 'expansion' then 1 end) as expanded_customers,
        count(case when mrr_movement_type = 'contraction' then 1 end) as contracted_customers,
        sum(seats) as active_seats

    from {{ ref('fct_mrr_movements') }}
    group by month_start_date

),

revenue as (

    select
        month_start_date,
        sum(recognized_revenue) as recognized_revenue,
        sum(recognized_recurring_revenue) as recognized_recurring_revenue,
        sum(recognized_one_time_revenue) as recognized_one_time_revenue,
        sum(billed_amount) as billed_amount,
        sum(collected_amount) as collected_amount,
        sum(invoice_count) as invoice_count

    from {{ ref('fct_revenue') }}
    group by month_start_date

),

signups as (

    select
        signup_month as month_start_date,
        count(*) as signups

    from {{ ref('dim_customers') }}
    group by signup_month

),

joined as (

    select
        months.month_start_date,
        months.month_end_date,
        coalesce(mrr_movements.mrr, 0) as mrr,
        coalesce(mrr_movements.mrr, 0) * 12 as arr,
        coalesce(mrr_movements.beginning_mrr, 0) as beginning_mrr,
        coalesce(mrr_movements.new_mrr, 0) as new_mrr,
        coalesce(mrr_movements.expansion_mrr, 0) as expansion_mrr,
        coalesce(mrr_movements.reactivation_mrr, 0) as reactivation_mrr,
        coalesce(mrr_movements.contraction_mrr, 0) as contraction_mrr,
        coalesce(mrr_movements.churned_mrr, 0) as churned_mrr,
        coalesce(mrr_movements.active_customers, 0) as active_customers,
        coalesce(mrr_movements.new_customers, 0) as new_customers,
        coalesce(mrr_movements.churned_customers, 0) as churned_customers,
        coalesce(mrr_movements.reactivated_customers, 0) as reactivated_customers,
        coalesce(mrr_movements.expanded_customers, 0) as expanded_customers,
        coalesce(mrr_movements.contracted_customers, 0) as contracted_customers,
        coalesce(mrr_movements.active_seats, 0) as active_seats,
        coalesce(signups.signups, 0) as signups,
        coalesce(revenue.recognized_revenue, 0) as recognized_revenue,
        coalesce(revenue.recognized_recurring_revenue, 0) as recognized_recurring_revenue,
        coalesce(revenue.recognized_one_time_revenue, 0) as recognized_one_time_revenue,
        coalesce(revenue.billed_amount, 0) as billed_amount,
        coalesce(revenue.collected_amount, 0) as collected_amount,
        coalesce(revenue.invoice_count, 0) as invoice_count

    from months
    left join mrr_movements
        on months.month_start_date = mrr_movements.month_start_date
    left join revenue
        on months.month_start_date = revenue.month_start_date
    left join signups
        on months.month_start_date = signups.month_start_date

),

with_lags as (

    select
        *,
        lag(mrr) over (order by month_start_date) as prior_month_mrr,
        lag(active_customers) over (order by month_start_date) as prior_month_active_customers,
        lag(recognized_revenue) over (order by month_start_date) as prior_month_recognized_revenue,
        sum(billed_amount) over (order by month_start_date rows between unbounded preceding and current row) as cumulative_billed_amount,
        sum(recognized_revenue) over (order by month_start_date rows between unbounded preceding and current row) as cumulative_recognized_revenue

    from joined

),

ratios as (

    select
        month_start_date,
        month_end_date,
        mrr,
        arr,
        beginning_mrr,
        new_mrr,
        expansion_mrr,
        reactivation_mrr,
        contraction_mrr,
        churned_mrr,
        mrr - beginning_mrr as net_new_mrr,
        active_customers,
        new_customers,
        churned_customers,
        reactivated_customers,
        expanded_customers,
        contracted_customers,
        active_seats,
        signups,
        recognized_revenue,
        recognized_recurring_revenue,
        recognized_one_time_revenue,
        billed_amount,
        collected_amount,
        invoice_count,
        -- Billed but not yet earned: the simplified deferred revenue balance.
        cumulative_billed_amount - cumulative_recognized_revenue as deferred_revenue_balance,
        case when active_customers > 0 then mrr / active_customers end as arpu,
        case when prior_month_mrr > 0 then (mrr - prior_month_mrr) / prior_month_mrr end as mrr_growth_rate,
        case when prior_month_recognized_revenue > 0
            then (recognized_revenue - prior_month_recognized_revenue) / prior_month_recognized_revenue
        end as recognized_revenue_growth_rate,
        case when prior_month_active_customers > 0 then churned_customers / prior_month_active_customers end as customer_churn_rate,
        case when beginning_mrr > 0 then churned_mrr / beginning_mrr end as mrr_churn_rate,
        case when beginning_mrr > 0 then (beginning_mrr - churned_mrr - contraction_mrr) / beginning_mrr end as gross_revenue_retention,
        case when beginning_mrr > 0 then (beginning_mrr - churned_mrr - contraction_mrr + expansion_mrr) / beginning_mrr end as net_revenue_retention

    from with_lags

)

select * from ratios
