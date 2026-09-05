-- Decompose the change in gross profit into price, volume, mix and cost effects

WITH sku_totals AS (
    SELECT 
        product_id,
        
        -- 2024 Baseline
        SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2024 THEN quantity ELSE 0 END) AS q_24,
        SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2024 THEN net_revenue ELSE 0 END) AS rev_24,
        SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2024 THEN cogs ELSE 0 END) AS cogs_24,
        
        -- 2025 Current
        SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2025 THEN quantity ELSE 0 END) AS q_25,
        SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2025 THEN net_revenue ELSE 0 END) AS rev_25,
        SUM(CASE WHEN EXTRACT(YEAR FROM transaction_date::DATE) = 2025 THEN cogs ELSE 0 END) AS cogs_25
    FROM sales_ledger
    GROUP BY product_id
),
sku_rates AS (
    SELECT
        product_id,
        q_24,
        q_25,
        (rev_24 - cogs_24) AS gp_24,
        (rev_25 - cogs_25) AS gp_25,
        
        -- Unit Prices, Costs, and Margins
        CASE 
            WHEN q_24 > 0 
                THEN rev_24 / q_24 
            ELSE 0 
        END AS p_24,
        CASE 
            WHEN q_25 > 0 
                THEN rev_25 / q_25 
            ELSE 0 
        END AS p_25,
        CASE 
            WHEN q_24 > 0 
                THEN cogs_24 / q_24 
            ELSE 0 
        END AS c_24,
        CASE 
            WHEN q_25 > 0 
                THEN cogs_25 / q_25 
            ELSE 0 
        END AS c_25,
        CASE 
            WHEN q_24 > 0 
                THEN (rev_24 - cogs_24) / q_24 
            ELSE 0 
        END AS m_24
    FROM sku_totals
),
totals AS (
    SELECT 
        SUM(q_24) AS total_q_24,
        SUM(q_25) AS total_q_25,
        SUM(q_25) / NULLIF(SUM(q_24), 0) AS vol_factor,
        SUM(gp_24) AS gp_2024,
        SUM(gp_25) AS gp_2025
    FROM sku_rates
),
drivers AS (
    SELECT
        -- Price Effect: Impact of selling price / discount changes
        SUM(r.q_25 * (r.p_25 - r.p_24)) AS price_effect,
        
        -- Volume Effect: Overall growth in units sold across the business
        SUM((r.q_24 * (t.vol_factor - 1)) * r.m_24) AS volume_effect,
        
        -- Mix Effect: Shift in demand toward higher or lower margin products
        SUM((r.q_25 - (r.q_24 * t.vol_factor)) * r.m_24) AS mix_effect,
        
        -- Cost Effect: Impact of unit inventory cost inflation
        SUM(r.q_25 * (r.c_24 - r.c_25)) AS cost_effect
    FROM sku_rates r
    CROSS JOIN totals t
)
SELECT '1. 2024 Gross Profit' AS driver, ROUND(gp_2024, 2) AS amount FROM totals
UNION ALL
SELECT '2. Price Effect', ROUND(price_effect, 2) FROM drivers
UNION ALL
SELECT '3. Volume Effect', ROUND(volume_effect, 2) FROM drivers
UNION ALL
SELECT '4. Mix Effect', ROUND(mix_effect, 2) FROM drivers
UNION ALL
SELECT '5. Cost Effect', ROUND(cost_effect, 2) FROM drivers
UNION ALL
SELECT '6. 2025 Gross Profit', ROUND(gp_2025, 2) FROM totals;





