-- The sum of current MRR on dim_customers must equal MRR for the snapshot
-- month in metrics_monthly. The two are computed by different paths
-- (latest open version vs. month-end spine) and must agree.

with customer_total as (

    select sum(current_mrr) as mrr from {{ ref('dim_customers') }}

),

metrics_total as (

    select mrr
    from {{ ref('metrics_monthly') }}
    where month_start_date = date_trunc('month', cast('{{ var("as_of_date") }}' as date))

)

select
    customer_total.mrr as customer_mrr,
    metrics_total.mrr as metrics_mrr

from customer_total
cross join metrics_total
where abs(customer_total.mrr - metrics_total.mrr) > 0.01
