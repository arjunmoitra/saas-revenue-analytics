-- MRR retention by first-paid-month cohort: what share of each cohort's
-- starting MRR is still on the books N months later. Values above 100% mean
-- expansion outweighed churn.

with cohort_base as (

    select
        first_mrr_month as cohort_month,
        sum(new_mrr) as cohort_starting_mrr

    from {{ ref('fct_mrr_movements') }}
    where mrr_movement_type = 'new'
    group by first_mrr_month

),

cohort_months as (

    select
        first_mrr_month as cohort_month,
        months_since_first_paid,
        sum(mrr) as cohort_mrr,
        count(case when is_active then 1 end) as active_customers

    from {{ ref('fct_mrr_movements') }}
    group by first_mrr_month, months_since_first_paid

)

select
    cohort_months.cohort_month,
    cohort_months.months_since_first_paid,
    cohort_months.active_customers,
    cohort_months.cohort_mrr,
    round(cohort_months.cohort_mrr / cohort_base.cohort_starting_mrr * 100, 1) as mrr_retention_pct

from cohort_months
inner join cohort_base
    on cohort_months.cohort_month = cohort_base.cohort_month
where cohort_months.months_since_first_paid in (0, 3, 6, 12, 24)
order by cohort_months.cohort_month, cohort_months.months_since_first_paid
