-- Why customers cancel, by the tier they were on when they left. Cancellation
-- reason is captured at the subscription version that was cancelled.

select
    plan_tier,
    coalesce(cancellation_reason, 'not_given') as cancellation_reason,
    count(*) as cancellations,
    round(sum(mrr), 2) as mrr_lost,
    round(avg(duration_days) / 30.4, 1) as avg_months_on_version

from {{ ref('dim_subscriptions') }}
where subscription_status = 'canceled'
group by plan_tier, cancellation_reason
order by mrr_lost desc
