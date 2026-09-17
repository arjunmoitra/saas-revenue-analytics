-- Revenue recognised across all months must sum back to the original line
-- item amount, to the cent. Rounding drift here would silently leak revenue.

with recognized as (

    select
        line_item_id,
        sum(recognized_revenue) as recognized_total

    from {{ ref('int_revenue_recognition') }}
    group by line_item_id

),

line_items as (

    select
        line_items.line_item_id,
        line_items.amount

    from {{ ref('stg_invoice_line_items') }} as line_items
    inner join {{ ref('stg_invoices') }} as invoices
        on line_items.invoice_id = invoices.invoice_id
    where invoices.invoice_status <> 'void'

)

select
    line_items.line_item_id,
    line_items.amount,
    recognized.recognized_total

from line_items
left join recognized
    on line_items.line_item_id = recognized.line_item_id
where recognized.recognized_total is null
    or abs(line_items.amount - recognized.recognized_total) > 0.001
