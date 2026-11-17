{{
    config(
        materialized = 'table',
    )
}}

with

base_dates as (
    {{
        dbt.date_spine(
            'day',
            "DATE('2000-01-01')",
            "DATE('2030-01-01')"
        )
    }}
),

final as (
    select
        cast(date_day as date) as date_day
    from base_dates
)

select *
from final
-- Retain historical dates so cumulative metrics can join to older orders.
where date_day < dateadd(day, 30, current_date())
