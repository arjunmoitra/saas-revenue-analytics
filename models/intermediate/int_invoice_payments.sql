{#-
  One row per invoice summarising its payment activity: gross charges,
  refunds, net cash collected, failed attempts and timing. Refunds are stored
  as negative amounts in staging, so net collected is a plain sum of succeeded
  rows.
-#}

with payments as (

    select * from {{ ref('stg_payments') }}

),

summarised as (

    select
        invoice_id,
        sum(case when payment_status = 'succeeded' and payment_type = 'charge' then amount else 0 end) as amount_charged,
        sum(case when payment_status = 'succeeded' and payment_type = 'refund' then -amount else 0 end) as amount_refunded,
        sum(case when payment_status = 'succeeded' then amount else 0 end) as net_amount_collected,
        count(case when payment_status = 'failed' then 1 end) as failed_attempt_count,
        count(case when payment_status = 'succeeded' and payment_type = 'charge' then 1 end) as successful_charge_count,
        min(case when payment_status = 'succeeded' and payment_type = 'charge' then paid_date end) as first_payment_date,
        max(case when payment_status = 'succeeded' and payment_type = 'charge' then paid_date end) as last_payment_date

    from payments
    group by invoice_id

)

select * from summarised
