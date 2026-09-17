{#-
  Month spine from the configured start date through the snapshot month.
  Every monthly model joins to this so months with no activity still appear.
-#}

with spine as (

    select unnest(generate_series(
        cast('{{ var("metrics_start_date") }}' as date),
        date_trunc('month', cast('{{ var("as_of_date") }}' as date)),
        interval 1 month
    )) as month_start

),

months as (

    select
        cast(month_start as date) as month_start_date,
        cast(month_start + interval 1 month - interval 1 day as date) as month_end_date,
        cast(month_start + interval 1 month - interval 1 day as date) <= cast('{{ var("as_of_date") }}' as date) as is_complete_month

    from spine

)

select * from months
