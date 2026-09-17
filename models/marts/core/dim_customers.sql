{#-
  One row per customer with firmographics and a summary of their subscription
  lifecycle as of the snapshot date.
-#}

with customers as (

    select * from {{ ref('stg_customers') }}

),

history as (

    select * from {{ ref('int_customer_subscription_history') }}

),

billing as (

    select
        customer_id,
        count(*) as invoice_count,
        sum(total_amount) as lifetime_billed_amount

    from {{ ref('stg_invoices') }}
    where invoice_status <> 'void'
    group by customer_id

),

joined as (

    select
        customers.customer_id,
        customers.company_name,
        customers.primary_email,
        customers.country_code,
        customers.country_name,
        customers.industry,
        customers.segment,
        customers.acquisition_channel,
        cast(customers.created_at as date) as signup_date,
        date_trunc('month', cast(customers.created_at as date)) as signup_month,
        history.customer_status,
        history.first_trial_start_date,
        history.first_paid_start_date,
        date_trunc('month', history.first_paid_start_date) as first_paid_month,
        history.churned_date,
        history.has_open_subscription as is_active,
        history.current_mrr_amount as current_mrr,
        history.current_mrr_amount * 12 as current_arr,
        history.latest_subscription_id,
        history.latest_plan_id,
        history.latest_plan_tier,
        history.latest_billing_interval,
        history.latest_quantity as latest_seats,
        history.latest_subscription_status,
        history.latest_cancellation_reason,
        history.subscription_version_count,
        history.upgrade_count,
        history.downgrade_count,
        history.seat_expansion_count,
        history.seat_contraction_count,
        history.cancellation_count,
        history.reactivation_count,
        -- Whole months of paid service between first paid start and either the
        -- churn date or the snapshot date.
        case
            when history.first_paid_start_date is null then 0
            else date_diff(
                'month',
                history.first_paid_start_date,
                coalesce(history.churned_date, cast('{{ var("as_of_date") }}' as date))
            )
        end as paid_tenure_months,
        coalesce(billing.invoice_count, 0) as invoice_count,
        coalesce(billing.lifetime_billed_amount, 0) as lifetime_billed_amount

    from customers
    left join history
        on customers.customer_id = history.customer_id
    left join billing
        on customers.customer_id = billing.customer_id

)

select * from joined
