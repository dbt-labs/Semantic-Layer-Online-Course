with customer_totals as (
    select sum(lifetime_spend) as lifetime_spend
    from {{ ref('dim_customers') }}
),
order_totals as (
    select sum(orders.order_total) as order_total
    from {{ ref('fct_orders') }} as orders
    inner join {{ ref('stg_customers') }} as customers
        on orders.customer_id = customers.customer_id
),
violations as (
    select 'customer_spend_does_not_reconcile' as issue
    from customer_totals
    cross join order_totals
    where abs(coalesce(customer_totals.lifetime_spend, 0) - coalesce(order_totals.order_total, 0)) > 0.01

    union all

    select 'order_date_missing_from_time_spine' as issue
    from {{ ref('fct_orders') }} as orders
    left join {{ ref('time_spine_daily') }} as spine
        on cast(orders.ordered_at as date) = spine.date_day
    where spine.date_day is null

    union all

    select 'item_timestamp_missing_or_inconsistent' as issue
    from {{ ref('fct_order_items') }}
    where ordered_at is null
        or ordered_at is distinct from ordered_at_dt
)
select * from violations
