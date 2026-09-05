-- Attribute price, volume, mix and cost effects to individual SKUs.

WITH sku_totals AS (
    SELECT 
        p.product_id,
        p.product_category,
        p.product_subcategory,
        
        -- 2024 Baseline
        COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2024 THEN quantity ELSE 0 END), 0) AS q_24,
        COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2024 THEN net_revenue ELSE 0 END), 0) AS rev_24,
        COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2024 THEN cogs ELSE 0 END), 0) AS cogs_24,
        
        -- 2025 Current
        COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2025 THEN quantity ELSE 0 END), 0) AS q_25,
        COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2025 THEN net_revenue ELSE 0 END), 0) AS rev_25,
        COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2025 THEN cogs ELSE 0 END), 0) AS cogs_25
    FROM sales_ledger s
    LEFT JOIN products p ON s.product_id = p.product_id
    GROUP BY p.product_id, p.product_category, p.product_subcategory
),
sku_rates AS (
    SELECT
        product_id,
        product_category,
        product_subcategory,
        q_24,
        q_25,
        (rev_24 - cogs_24) AS gp_24,
        (rev_25 - cogs_25) AS gp_25,
        
        -- Unit economics
        CASE WHEN q_24 > 0 THEN rev_24 / q_24 ELSE 0 END AS p_24,
        CASE WHEN q_25 > 0 THEN rev_25 / q_25 ELSE 0 END AS p_25,
        CASE WHEN q_24 > 0 THEN cogs_24 / q_24 ELSE 0 END AS c_24,
        CASE WHEN q_25 > 0 THEN cogs_25 / q_25 ELSE 0 END AS c_25,
        CASE WHEN q_24 > 0 THEN (rev_24 - cogs_24) / q_24 ELSE 0 END AS unit_gross_profit_24
    FROM sku_totals
),
totals AS (
    SELECT 
        SUM(q_25) / NULLIF(SUM(q_24), 0) AS vol_factor
    FROM sku_rates
)
SELECT
    r.product_id,
    r.product_category,
    r.product_subcategory,
    r.q_24 AS units_2024,
    r.q_25 AS units_2025,
    ROUND(r.gp_24, 2) AS gp_2024,
    
    -- PVMC Drivers per Product
    ROUND((r.q_24 * (t.vol_factor - 1)) * r.unit_gross_profit_24, 2) AS volume_effect,
    ROUND((r.q_25 - (r.q_24 * t.vol_factor)) * r.unit_gross_profit_24, 2) AS mix_effect,
    ROUND(r.q_25 * (r.p_25 - r.p_24), 2) AS price_effect,
    ROUND(r.q_25 * (r.c_24 - r.c_25), 2) AS cost_effect,
    
    ROUND(r.gp_25, 2) AS gp_2025,
    ROUND(r.gp_25 - r.gp_24, 2) AS gross_profit_change
FROM sku_rates r
CROSS JOIN totals t
ORDER BY gross_profit_change ASC;