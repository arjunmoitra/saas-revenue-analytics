-- The customer-level MRR in fct_mrr_movements must equal the sum of the
-- subscription versions active at month end. Guards against the customer
-- spine dropping or duplicating months.

with subscription_level as (

    select
        customer_id,
        month_start_date,
        sum(mrr_amount) as mrr

    from {{ ref('int_subscription_mrr_monthly') }}
    group by customer_id, month_start_date

),

customer_level as (

    select
        customer_id,
        month_start_date,
        mrr

    from {{ ref('fct_mrr_movements') }}
    where mrr > 0

)

select
    coalesce(subscription_level.customer_id, customer_level.customer_id) as customer_id,
    coalesce(subscription_level.month_start_date, customer_level.month_start_date) as month_start_date,
    subscription_level.mrr as subscription_mrr,
    customer_level.mrr as customer_mrr

from subscription_level
full outer join customer_level
    on subscription_level.customer_id = customer_level.customer_id
    and subscription_level.month_start_date = customer_level.month_start_date
where subscription_level.mrr is null
    or customer_level.mrr is null
    or abs(subscription_level.mrr - customer_level.mrr) > 0.01
