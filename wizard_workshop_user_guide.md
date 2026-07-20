# dbt Wizard workshop — cheat sheet

This is the answer key: the exact prompt for each exercise, plus a step-by-step walkthrough of how it should resolve.   
---

## Small exercises

### 1\. Fill in missing tests and documentation

**Prompt:**

> fct\_orders has a full description and semantic model but no data tests. Add appropriate tests based on the entities and columns already defined.

**Walkthrough:**

1. Wizard reads `fct_orders.yml` and sees `order_id` declared as the primary entity, `location_id` and `customer_id` as foreign entities.  
2. It proposes `unique` \+ `not_null` on `order_id`.  
3. It proposes `relationships` tests from `location_id` → wherever locations are defined, and `customer_id` → `stg_customers`.  
4. It should *not* invent a description — one already exists — and shouldn't touch the semantic model YAML, just add a `tests:` (or `data_tests:`) block.

**Recommended model:** `fct_orders` (or `fct_order_items` / `dim_customers` as alternates — all three have the identical gap).

---

### 2\. Rename a column and see what breaks

**Prompt:**

> Rename order\_total to gross\_order\_amount in stg\_orders, and update every downstream reference — including the semantic layer — so nothing breaks.

**Walkthrough:**

1. Wizard should first surface the full list of references before editing: the column in `stg_orders.sql` itself; the `expr: order_total` lines in `fct_orders.yml` for metrics `order_total`, `food_order_amount`, `max_order_value`, `min_order_value`, `order_value_p99`, `discrete_order_value_p99`; and the `Dimension('order_id__order_total')` filter used in the `large_order` metric.  
2. It renames the column in `stg_orders.sql`.  
3. It updates every `expr:` and filter reference listed above to use `gross_order_amount`.  
4. If it misses one (commonly `large_order`'s filter, since it's a string inside a Jinja filter block rather than a plain `expr:`), that's your natural setup for exercise 4\.

**Recommended model:** `stg_orders` (source of the rename), `fct_orders.yml` (where the fallout lives).

---

### 3\. Ask Wizard to explain a model

**Prompt:**

> Explain what dim\_customers represents, where each column and metric comes from, and what downstream consumes it.

**Walkthrough:**

1. Wizard should describe the grain (one row per customer) and summarize how `count_lifetime_orders`, `lifetime_spend_pretax`, `lifetime_spend`, and `customer_type` are each derived from `fct_orders` and `fct_order_items`.  
2. It should list `stg_customers`, `fct_orders`, and `fct_order_items` as direct upstream dependencies.  
3. A strong answer also surfaces that `reports/pages/customers/index.md` (the Evidence.dev report) queries this model directly — that's the real downstream consumer in this repo, and it's worth calling out explicitly if the room doesn't ask about it.

**Recommended model:** `dim_customers`.

---

### 4\. Debug a metric that's suddenly broken

**Prompt:**

> The large\_order metric is failing to compile. Investigate why and fix it.

*(Only works after exercise 2 has been run and the rename wasn't fully propagated — if exercise 2 went perfectly, deliberately revert just the `large_order` filter back to `order_total` to set this up.)*

**Walkthrough:**

1. Wizard should trace: `large_order` metric → its `filter` referencing `Dimension('order_id__order_total')` → the `order_total` dimension declaration on `fct_orders` → the fact that the underlying column was renamed to `gross_order_amount` in `stg_orders`.  
2. It should identify the mismatch as the root cause (not just report "the filter is invalid").  
3. Fix: update the filter to `Dimension('order_id__gross_order_amount')` and correct the dimension definition name/expr in `fct_orders.yml` if the dimension label itself also changed.

**Recommended model:** `fct_orders.yml`, specifically the `large_order` metric.

---

## Medium exercises

### 1\. Clean up inconsistent macro usage

**Prompt:**

> stg\_orders, stg\_products, and stg\_supplies all convert cents to dollars with slightly different inline logic. Have them all call the existing cents\_to\_dollars macro instead.

**Walkthrough:**

1. Wizard should recognize `macros/cents_to_dollars.sql` already exists (`{% macro cents_to_dollars(column_name, precision=2) %}`).  
2. It replaces `(order_total / 100.0)` and `(tax_paid / 100.0)` in `stg_orders.sql`, `(price / 100.0)` in `stg_products.sql`, and `(cost / 100.0)` in `stg_supplies.sql` with `{{ cents_to_dollars('order_total') }}` etc.  
3. It should not write a second macro or duplicate the existing one — reusing what's already there is the whole point.

**Recommended models:** `stg_orders`, `stg_products`, `stg_supplies` (all three together).

---

### 2\. Convert a full-refresh model to incremental

**Prompt:**

> stg\_orders already has a unique\_key set but rebuilds fully every run. Convert it to an incremental model.

**Walkthrough:**

1. Wizard should change `materialized = 'table'` to `materialized = 'incremental'` in the config block, keeping the existing `unique_key = 'order_id'` rather than redefining it.  
2. It should add an `is_incremental()` filter — most naturally on `ordered_at` (there's no explicit ETL-loaded-at timestamp in this source, so filtering on `ordered_at > (select max(ordered_at) from {{ this }})` is a reasonable, explainable choice).  
3. Bonus: ask Wizard to validate the build afterward to confirm the incremental logic actually compiles and runs.

**Recommended model:** `stg_orders`.

---

## Hard exercises

### 1\. Build a new metric

**Prompt:**

> Create a new metric for repeat-purchase rate or customer retention, following the patterns already used in fct\_orders.yml and dim\_customers.yml, and explain what would consume it and where it'd show up.

**Walkthrough:**

1. A reasonable metric: `repeat_purchase_rate` as a `ratio` metric — numerator `customers` where `count_lifetime_orders > 1` (i.e., reuse or extend the existing `is_repeat_buyer` logic already computed in `dim_customers.sql`), denominator total `customers`.  
2. It should be added to `dim_customers.yml` (or a new semantic model file) using the same `type: ratio` / `numerator` / `denominator` structure already used for `food_order_pct` in `fct_orders.yml`.  
3. On consumption: Wizard should mention that `reports/pages/customers/index.md` already surfaces per-customer order history and could plausibly add this metric, and/or that a Semantic Layer / BI tool connection would expose it more broadly.

**Recommended models:** `dim_customers.yml` (new metric lives here), referencing logic already in `dim_customers.sql`.

---

### 2\. Validate a risky change before shipping it

**Prompt:**

> I'm about to ship the order\_total rename. Validate the whole semantic layer compiles and nothing downstream is broken before I push.

**Walkthrough:**

1. Wizard should check metric/semantic-model compilation project-wide, not just `fct_orders.yml` — i.e., confirm `dim_customers.yml` and `fct_order_items.yml` still resolve correctly too, since they reference `fct_orders`.  
2. It should flag any metric still pointing at the old `order_total` name (this is where a half-finished exercise 2 gets caught, if it wasn't caught back in exercise 4).  
3. A strong answer also suggests running `dbt build` (or the MetricFlow/semantic validation equivalent) rather than just a static compile check, and reports back pass/fail.

**Recommended model:** `fct_orders.yml` and its full dependency chain (`dim_customers.yml`, `fct_order_items.yml`).

---

## Quick-reference table

| \# | Exercise | Recommended model(s) |
| :---- | :---- | :---- |
| Small 1 | Tests/docs for existing model | `fct_orders` (or `fct_order_items`, `dim_customers`) |
| Small 2 | Column rename ripple | `stg_orders` → `fct_orders.yml` |
| Small 3 | Explain lineage | `dim_customers` |
| Small 4 | Broken metric | `fct_orders.yml` → `large_order` metric |
| Medium 1 | Reusable macro | `stg_orders`, `stg_products`, `stg_supplies` |
| Medium 2 | Incremental conversion | `stg_orders` |
| Hard 1 | New metric | `dim_customers.yml` |
| Hard 2 | Validate before shipping | `fct_orders.yml` \+ dependents |

