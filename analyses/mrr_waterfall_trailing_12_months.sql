-- MRR waterfall for the trailing 12 months: how beginning MRR became ending
-- MRR through new, expansion, reactivation, contraction and churn.
-- Run with: dbt compile -s mrr_waterfall_trailing_12_months, then execute target/compiled/...

select
    month_start_date,
    beginning_mrr,
    new_mrr,
    expansion_mrr,
    reactivation_mrr,
    -contraction_mrr as contraction_mrr,
    -churned_mrr as churned_mrr,
    mrr as ending_mrr,
    net_new_mrr,
    round(mrr_growth_rate * 100, 2) as mrr_growth_pct,
    round(net_revenue_retention * 100, 1) as nrr_pct

from {{ ref('metrics_monthly') }}
where month_start_date > date_trunc('month', cast('{{ var("as_of_date") }}' as date)) - interval 12 month
order by month_start_date
