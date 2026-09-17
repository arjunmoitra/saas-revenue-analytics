-- Month-end MRR must equal the prior month's MRR plus all movements. This is
-- the accounting identity behind the MRR waterfall; if it breaks, the
-- movement classification in int_customer_mrr_monthly has a gap.

select
    customer_id,
    month_start_date,
    prior_mrr,
    mrr,
    new_mrr,
    expansion_mrr,
    reactivation_mrr,
    contraction_mrr,
    churned_mrr

from {{ ref('fct_mrr_movements') }}
where abs(
        prior_mrr + new_mrr + expansion_mrr + reactivation_mrr - contraction_mrr - churned_mrr - mrr
    ) > 0.01
