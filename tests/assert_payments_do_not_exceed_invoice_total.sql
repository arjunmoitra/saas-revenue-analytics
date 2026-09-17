-- Successful charges on an invoice may never exceed the invoice total, and
-- refunds may never exceed what was charged. Either would indicate duplicate
-- payment records or an unlinked refund.

select
    invoice_id,
    total_amount,
    amount_charged,
    amount_refunded

from {{ ref('fct_invoices') }}
where amount_charged > total_amount
    or amount_refunded > amount_charged
