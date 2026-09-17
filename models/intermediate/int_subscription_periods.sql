{#-
  One row per *paid* subscription version, enriched with plan pricing, a
  monthly-normalised recurring amount (MRR) and a classification of how this
  version differs from the customer's previous paid version.

  Trials are excluded here because they never bill and never count toward MRR.
  Open versions get an effective end date equal to the snapshot date so that
  interval logic downstream never has to handle nulls.
-#}

with subscriptions as (

    select * from {{ ref('stg_subscriptions') }}
    where not is_trial

),

plans as (

    select * from {{ ref('stg_plans') }}

),

priced as (

    select
        subscriptions.subscription_id,
        subscriptions.customer_id,
        subscriptions.plan_id,
        plans.plan_name,
        plans.plan_tier,
        plans.plan_tier_rank,
        plans.billing_interval,
        plans.unit_price,
        subscriptions.quantity,
        subscriptions.subscription_status,
        subscriptions.start_date,
        subscriptions.end_date,
        coalesce(subscriptions.end_date, cast('{{ var("as_of_date") }}' as date)) as effective_end_date,
        subscriptions.end_date is null as is_open,
        subscriptions.canceled_at,
        subscriptions.cancellation_reason,
        plans.unit_price * subscriptions.quantity as recurring_amount,
        {{ monthly_normalized_amount('plans.unit_price * subscriptions.quantity', 'plans.billing_interval') }} as mrr_amount

    from subscriptions
    inner join plans
        on subscriptions.plan_id = plans.plan_id

),

with_previous as (

    select
        *,
        row_number() over (partition by customer_id order by start_date) as version_number,
        lag(plan_tier_rank) over (partition by customer_id order by start_date) as previous_plan_tier_rank,
        lag(quantity) over (partition by customer_id order by start_date) as previous_quantity,
        lag(billing_interval) over (partition by customer_id order by start_date) as previous_billing_interval,
        lag(mrr_amount) over (partition by customer_id order by start_date) as previous_mrr_amount,
        lag(effective_end_date) over (partition by customer_id order by start_date) as previous_end_date

    from priced

),

classified as (

    select
        *,
        case
            when previous_end_date is null then 'new'
            -- A gap between the previous version ending and this one starting means
            -- the customer churned and later came back.
            when start_date > previous_end_date + interval 1 day then 'reactivation'
            when plan_tier_rank > previous_plan_tier_rank then 'upgrade'
            when plan_tier_rank < previous_plan_tier_rank then 'downgrade'
            when quantity > previous_quantity then 'seat_expansion'
            when quantity < previous_quantity then 'seat_contraction'
            when billing_interval <> previous_billing_interval then 'interval_change'
            else 'no_change'
        end as change_type,
        mrr_amount - coalesce(previous_mrr_amount, 0) as mrr_change_vs_previous

    from with_previous

)

select
    subscription_id,
    customer_id,
    plan_id,
    plan_name,
    plan_tier,
    plan_tier_rank,
    billing_interval,
    unit_price,
    quantity,
    recurring_amount,
    mrr_amount,
    subscription_status,
    start_date,
    end_date,
    effective_end_date,
    is_open,
    canceled_at,
    cancellation_reason,
    version_number,
    change_type,
    mrr_change_vs_previous

from classified
