-- Illustrates the difference between billing and revenue recognition on an
-- annual invoice: the full amount is billed in one month but earned over
-- twelve. Picks the largest annual invoice in the dataset.

with sample_invoice as (

    select invoice_id
    from {{ ref('fct_invoices') }}
    where billing_interval = 'annual'
        and invoice_status = 'paid'
    order by total_amount desc
    limit 1

)

select
    recognition.invoice_id,
    recognition.line_type,
    recognition.revenue_month,
    recognition.service_days_in_month,
    recognition.line_amount as invoiced_line_amount,
    recognition.recognized_revenue,
    sum(recognition.recognized_revenue) over (
        partition by recognition.line_item_id
        order by recognition.revenue_month
        rows between unbounded preceding and current row
    ) as cumulative_recognized

from {{ ref('int_revenue_recognition') }} as recognition
inner join sample_invoice
    on recognition.invoice_id = sample_invoice.invoice_id
order by recognition.line_type, recognition.revenue_month
