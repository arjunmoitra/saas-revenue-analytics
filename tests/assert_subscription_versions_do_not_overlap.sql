-- A customer's paid subscription versions must be sequential: each version
-- has to start after the previous one ended. Overlapping versions would
-- double-count MRR.

with ordered as (

    select
        customer_id,
        subscription_id,
        start_date,
        effective_end_date,
        lag(effective_end_date) over (partition by customer_id order by start_date) as previous_end_date

    from {{ ref('dim_subscriptions') }}
    where not is_trial

)

select *
from ordered
where start_date <= previous_end_date
