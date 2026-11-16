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
        cast(date_day as date) as date_day,
        
        -- Fiscal year starts Feb 1. Shift back one month, truncate, shift forward.
        dateadd(month, 1, date_trunc('year',    dateadd(month, -1, date_day))) as fiscal_year_start,
        dateadd(month, 1, date_trunc('quarter', dateadd(month, -1, date_day))) as fiscal_quarter_start
    from base_dates
)

select *
from final
where date_day > dateadd(year, -15, current_date())  -- Keep recent dates only
  and date_day < dateadd(day, 30, current_date())