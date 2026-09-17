-- Trial subscription versions must not have invoices; if they did, MRR and
-- recognised revenue would disagree about when a customer started paying.

select
    invoices.invoice_id,
    invoices.subscription_id

from {{ ref('fct_invoices') }} as invoices
inner join {{ ref('dim_subscriptions') }} as subscriptions
    on invoices.subscription_id = subscriptions.subscription_id
where subscriptions.is_trial
