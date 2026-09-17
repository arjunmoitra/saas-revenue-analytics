{#-
  One row per customer summarising their paid subscription history: when they
  first paid, whether they are currently active, what they are on today and how
  many plan changes they have made. Feeds dim_customers.
-#}

with periods as (

    select * from {{ ref('int_subscription_periods') }}

),

trials as (

    select
        customer_id,
        min(start_date) as first_trial_start_date

    from {{ ref('stg_subscriptions') }}
    where is_trial
    group by customer_id

),

customer_periods as (

    select
        customer_id,
        min(start_date) as first_paid_start_date,
        max(effective_end_date) as latest_end_date,
        max(case when is_open then 1 else 0 end) = 1 as has_open_subscription,
        count(*) as subscription_version_count,
        count(case when change_type = 'upgrade' then 1 end) as upgrade_count,
        count(case when change_type = 'downgrade' then 1 end) as downgrade_count,
        count(case when change_type = 'seat_expansion' then 1 end) as seat_expansion_count,
        count(case when change_type = 'seat_contraction' then 1 end) as seat_contraction_count,
        count(case when subscription_status = 'canceled' then 1 end) as cancellation_count,
        count(case when change_type = 'reactivation' then 1 end) as reactivation_count

    from periods
    group by customer_id

),

latest_version as (

    select
        customer_id,
        subscription_id as latest_subscription_id,
        plan_id as latest_plan_id,
        plan_tier as latest_plan_tier,
        billing_interval as latest_billing_interval,
        quantity as latest_quantity,
        mrr_amount as latest_mrr_amount,
        subscription_status as latest_subscription_status,
        end_date as latest_subscription_end_date,
        cancellation_reason as latest_cancellation_reason

    from periods
    qualify row_number() over (partition by customer_id order by start_date desc) = 1

),

all_customers as (

    select customer_id from {{ ref('stg_customers') }}

),

joined as (

    select
        all_customers.customer_id,
        trials.first_trial_start_date,
        customer_periods.first_paid_start_date,
        customer_periods.latest_end_date,
        coalesce(customer_periods.has_open_subscription, false) as has_open_subscription,
        coalesce(customer_periods.subscription_version_count, 0) as subscription_version_count,
        coalesce(customer_periods.upgrade_count, 0) as upgrade_count,
        coalesce(customer_periods.downgrade_count, 0) as downgrade_count,
        coalesce(customer_periods.seat_expansion_count, 0) as seat_expansion_count,
        coalesce(customer_periods.seat_contraction_count, 0) as seat_contraction_count,
        coalesce(customer_periods.cancellation_count, 0) as cancellation_count,
        coalesce(customer_periods.reactivation_count, 0) as reactivation_count,
        latest_version.latest_subscription_id,
        latest_version.latest_plan_id,
        latest_version.latest_plan_tier,
        latest_version.latest_billing_interval,
        latest_version.latest_quantity,
        latest_version.latest_subscription_status,
        latest_version.latest_cancellation_reason,
        case when customer_periods.has_open_subscription then latest_version.latest_mrr_amount else 0 end as current_mrr_amount,
        case
            when customer_periods.has_open_subscription then 'active'
            when customer_periods.first_paid_start_date is not null then 'churned'
            when trials.first_trial_start_date is not null then 'trial_only'
            else 'never_subscribed'
        end as customer_status,
        case
            when customer_periods.first_paid_start_date is null then null
            when customer_periods.has_open_subscription then null
            else latest_version.latest_subscription_end_date
        end as churned_date

    from all_customers
    left join customer_periods
        on all_customers.customer_id = customer_periods.customer_id
    left join latest_version
        on all_customers.customer_id = latest_version.customer_id
    left join trials
        on all_customers.customer_id = trials.customer_id

)

select * from joined
