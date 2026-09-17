-- Largest active accounts by ARR with their expansion history, useful for
-- account management and concentration risk review.

select
    customer_id,
    company_name,
    segment,
    country_code,
    latest_plan_tier,
    latest_billing_interval,
    latest_seats,
    current_arr,
    round(current_arr / sum(current_arr) over () * 100, 2) as pct_of_total_arr,
    round(sum(current_arr) over (order by current_arr desc rows between unbounded preceding and current row)
        / sum(current_arr) over () * 100, 2) as cumulative_pct_of_arr,
    paid_tenure_months,
    upgrade_count + seat_expansion_count as expansion_events,
    downgrade_count + seat_contraction_count as contraction_events

from {{ ref('dim_customers') }}
where is_active
order by current_arr desc
limit 25
