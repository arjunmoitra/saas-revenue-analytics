{#-
  One row per plan (tier x billing interval) with list pricing normalised to a
  monthly figure so MRR contribution per seat is available for any plan.
-#}

with plans as (

    select * from {{ ref('stg_plans') }}

),

final as (

    select
        plan_id,
        plan_name,
        plan_tier,
        plan_tier_rank,
        billing_interval,
        currency,
        unit_price,
        {{ monthly_normalized_amount('unit_price', 'billing_interval') }} as monthly_unit_price,
        is_active,
        created_at

    from plans

)

select * from final
