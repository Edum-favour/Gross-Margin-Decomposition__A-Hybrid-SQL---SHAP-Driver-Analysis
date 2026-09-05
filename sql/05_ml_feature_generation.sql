-- Generate transaction level features and the target variable for ML analysis

WITH transaction_metrics AS (
    SELECT
        t.transaction_id,
        t.order_id,
        CAST(t.transaction_date AS DATE) AS transaction_date,
        t.store_id,
        t.product_id,
        p.product_category,
        p.product_subcategory,
        t.quantity,
        t.unit_price,
        t.discount_rate,
        t.unit_cost,

        EXTRACT(YEAR FROM CAST(t.transaction_date AS DATE)) AS year,
        EXTRACT(MONTH FROM CAST(t.transaction_date AS DATE)) AS month,

        -- Order-level features
        SUM(t.quantity) OVER (
            PARTITION BY t.order_id
        ) AS order_units,

        COUNT(*) OVER (
            PARTITION BY t.order_id
        ) AS order_lines,

        -- Transaction financials
        t.quantity * t.unit_price AS list_revenue,

        t.quantity
            * t.unit_price
            * t.discount_rate AS discount_amount,

        t.quantity
            * t.unit_price
            * (1 - t.discount_rate) AS net_revenue,

        t.quantity * t.unit_cost AS cogs,

        (
            t.quantity
            * t.unit_price
            * (1 - t.discount_rate)
        ) - (
            t.quantity * t.unit_cost
        ) AS gross_profit,

        100 * (
            (
                t.quantity
                * t.unit_price
                * (1 - t.discount_rate)
            ) - (
                t.quantity * t.unit_cost
            )
        ) / NULLIF(
            t.quantity
            * t.unit_price
            * (1 - t.discount_rate),
            0
        ) AS gross_margin_pct

    FROM transactions AS t

    LEFT JOIN products AS p
        ON t.product_id = p.product_id
),

baseline_2024 AS (
    SELECT
        product_id,

        SUM(quantity) AS base_units,

        SUM(list_revenue)
            / NULLIF(SUM(quantity), 0)
            AS base_unit_price,

        SUM(cogs)
            / NULLIF(SUM(quantity), 0)
            AS base_unit_cost,

        SUM(discount_amount)
            / NULLIF(SUM(list_revenue), 0)
            AS base_discount_rate,

        100 * SUM(gross_profit)
            / NULLIF(SUM(net_revenue), 0)
            AS base_margin_pct

    FROM transaction_metrics

    WHERE year = 2024

    GROUP BY product_id
)

SELECT
    tm.*,
    b.base_unit_price,
    b.base_unit_cost,
    b.base_discount_rate,
    b.base_margin_pct,

    -- Unit-cost movement from product baseline
    100 * (
        tm.unit_cost
        / NULLIF(b.base_unit_cost, 0)
        - 1
    ) AS unit_cost_change_pct,

    -- List-price movement from product baseline
    100 * (
        tm.unit_price
        / NULLIF(b.base_unit_price, 0)
        - 1
    ) AS list_price_change_pct,

    -- Discount movement in percentage points
    100 * (
        tm.discount_rate
        - b.base_discount_rate
    ) AS discount_change_pp,

    -- ML target
    tm.gross_margin_pct
        - b.base_margin_pct
        AS margin_delta_pp

FROM transaction_metrics AS tm

INNER JOIN baseline_2024 AS b
    ON tm.product_id = b.product_id

WHERE tm.year = 2025

ORDER BY
    tm.transaction_date,
    tm.transaction_id;





