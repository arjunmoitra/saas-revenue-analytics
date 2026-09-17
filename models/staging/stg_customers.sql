with source as (

    select * from {{ source('billing', 'raw_customers') }}

),

country_codes as (

    select * from {{ ref('country_codes') }}

),

cleaned as (

    select
        customer_id,
        trim(company_name) as company_name,
        lower(trim(primary_email)) as primary_email,
        lower(trim(country)) as country_raw,
        trim(industry) as industry,
        -- Segment values arrive with inconsistent casing ("smb", "Smb", "SMB").
        case lower(trim(segment))
            when 'smb' then 'SMB'
            when 'mid-market' then 'Mid-Market'
            when 'enterprise' then 'Enterprise'
        end as segment,
        lower(trim(acquisition_channel)) as acquisition_channel,
        cast(created_at as timestamp) as created_at,
        cast(updated_at as timestamp) as updated_at

    from source

),

joined as (

    select
        cleaned.customer_id,
        cleaned.company_name,
        cleaned.primary_email,
        coalesce(country_codes.country_code, upper(cleaned.country_raw)) as country_code,
        coalesce(country_codes.country_name, cleaned.country_raw) as country_name,
        cleaned.industry,
        cleaned.segment,
        cleaned.acquisition_channel,
        cleaned.created_at,
        cleaned.updated_at

    from cleaned
    left join country_codes
        on cleaned.country_raw = country_codes.raw_value

)

select * from joined
