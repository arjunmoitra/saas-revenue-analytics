-- Every invoice's subtotal must equal the sum of its line items, and its total
-- must equal subtotal + tax. A mismatch means the billing extract is
-- inconsistent and revenue would be misstated.

select
    invoice_id,
    subtotal_amount,
    line_items_subtotal,
    tax_amount,
    total_amount

from {{ ref('fct_invoices') }}
where subtotal_amount <> line_items_subtotal
    or total_amount <> subtotal_amount + tax_amount
