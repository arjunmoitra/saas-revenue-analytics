{#-
  One row per subscription version, including trials. Paid versions carry the
  MRR and change classification from int_subscription_periods; trials carry
  null MRR and change_type = 'trial'.
-#}

with all_versions as (

    select * from {{ ref('stg_subscriptions') }}

),

paid_periods as (

    select * from {{ ref('int_subscription_periods') }}

),

plans as (

    select * from {{ ref('dim_plans') }}

),

joined as (

    select
        all_versions.subscription_id,
        all_versions.customer_id,
        all_versions.plan_id,
        plans.plan_name,
        plans.plan_tier,
        plans.plan_tier_rank,
        plans.billing_interval,
        all_versions.previous_subscription_id,
        all_versions.quantity as seats,
        all_versions.is_trial,
        all_versions.subscription_status,
        all_versions.start_date,
        all_versions.end_date,
        coalesce(all_versions.end_date, cast('{{ var("as_of_date") }}' as date)) as effective_end_date,
        all_versions.end_date is null as is_open,
        all_versions.canceled_at,
        all_versions.cancellation_reason,
        paid_periods.recurring_amount,
        paid_periods.mrr_amount as mrr,
        paid_periods.mrr_amount * 12 as arr,
        paid_periods.version_number as paid_version_number,
        case when all_versions.is_trial then 'trial' else paid_periods.change_type end as change_type,
        paid_periods.mrr_change_vs_previous,
        date_diff('day', all_versions.start_date, coalesce(all_versions.end_date, cast('{{ var("as_of_date") }}' as date))) + 1 as duration_days

    from all_versions
    left join paid_periods
        on all_versions.subscription_id = paid_periods.subscription_id
    left join plans
        on all_versions.plan_id = plans.plan_id

)

select * from joined
