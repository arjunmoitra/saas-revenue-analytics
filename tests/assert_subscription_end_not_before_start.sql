-- A subscription version cannot end before it starts. Open versions have a
-- null end_date and are excluded.

select
    subscription_id,
    start_date,
    end_date

from {{ ref('dim_subscriptions') }}
where end_date < start_date
