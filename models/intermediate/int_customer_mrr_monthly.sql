{#-
  One row per customer per month from the customer's first paid month through
  the snapshot month, including months with zero MRR. Comparing each month to
  the prior month classifies the MRR movement:

    new           first month the customer ever has MRR
    expansion     MRR increased versus last month (upgrade or more seats)
    contraction   MRR decreased but is still > 0 (downgrade or fewer seats)
    churn         MRR went from > 0 to 0
    reactivation  MRR went from 0 back to > 0 for a previously churned customer
    retained      MRR unchanged and > 0
    inactive      MRR is 0 this month and was 0 last month

  The movement amounts satisfy the identity
    mrr = prior_mrr + new + expansion + reactivation - contraction - churned
  which is enforced by a singular test.
-#}

with months as (

    select * from {{ ref('int_months') }}

),

subscription_mrr as (

    select * from {{ ref('int_subscription_mrr_monthly') }}

),

customer_first_month as (

    select
        customer_id,
        min(month_start_date) as first_mrr_month

    from subscription_mrr
    group by customer_id

),

customer_months as (

    select
        customer_first_month.customer_id,
        months.month_start_date,
        months.month_end_date,
        customer_first_month.first_mrr_month

    from customer_first_month
    inner join months
        on months.month_start_date >= customer_first_month.first_mrr_month

),

monthly_mrr as (

    select
        customer_id,
        month_start_date,
        sum(mrr_amount) as mrr,
        sum(quantity) as seats,
        count(*) as active_subscription_count

    from subscription_mrr
    group by customer_id, month_start_date

),

with_prior as (

    select
        customer_months.customer_id,
        customer_months.month_start_date,
        customer_months.month_end_date,
        customer_months.first_mrr_month,
        coalesce(monthly_mrr.mrr, 0) as mrr,
        coalesce(monthly_mrr.seats, 0) as seats,
        coalesce(monthly_mrr.active_subscription_count, 0) as active_subscription_count,
        coalesce(
            lag(monthly_mrr.mrr) over (partition by customer_months.customer_id order by customer_months.month_start_date),
            0
        ) as prior_mrr

    from customer_months
    left join monthly_mrr
        on customer_months.customer_id = monthly_mrr.customer_id
        and customer_months.month_start_date = monthly_mrr.month_start_date

),

classified as (

    select
        customer_id,
        month_start_date,
        month_end_date,
        first_mrr_month,
        mrr,
        prior_mrr,
        seats,
        active_subscription_count,
        mrr > 0 as is_active,
        case
            when month_start_date = first_mrr_month then 'new'
            when prior_mrr = 0 and mrr > 0 then 'reactivation'
            when prior_mrr > 0 and mrr = 0 then 'churn'
            when mrr > prior_mrr then 'expansion'
            when mrr < prior_mrr then 'contraction'
            when mrr > 0 then 'retained'
            else 'inactive'
        end as mrr_movement_type

    from with_prior

),

amounts as (

    select
        *,
        case when mrr_movement_type = 'new' then mrr else 0 end as new_mrr,
        case when mrr_movement_type = 'expansion' then mrr - prior_mrr else 0 end as expansion_mrr,
        case when mrr_movement_type = 'contraction' then prior_mrr - mrr else 0 end as contraction_mrr,
        case when mrr_movement_type = 'churn' then prior_mrr else 0 end as churned_mrr,
        case when mrr_movement_type = 'reactivation' then mrr else 0 end as reactivation_mrr

    from classified

)

select * from amounts
