-- Service periods drive revenue recognition, so they must be well formed:
-- end on or after start, and contained within the invoice's own period.

select
    line_items.line_item_id,
    line_items.service_period_start,
    line_items.service_period_end,
    invoices.service_period_start as invoice_period_start,
    invoices.service_period_end as invoice_period_end

from {{ ref('stg_invoice_line_items') }} as line_items
inner join {{ ref('stg_invoices') }} as invoices
    on line_items.invoice_id = invoices.invoice_id
where line_items.service_period_end < line_items.service_period_start
    or line_items.service_period_start < invoices.service_period_start
    or line_items.service_period_end > invoices.service_period_end
