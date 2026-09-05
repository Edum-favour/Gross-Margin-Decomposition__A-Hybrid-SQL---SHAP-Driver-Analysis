-- compare year-over-year revenue, gross profit and gross margin performance

SELECT
    EXTRACT(YEAR FROM transaction_date::DATE) AS year,
    ROUND(SUM(net_revenue),2) AS total_revenue,
    ROUND(SUM(net_revenue - cogs), 2) AS gross_profit,
    ROUND(100 * (SUM(net_revenue - cogs) / SUM(net_revenue)), 2) AS gross_margin
FROM
    sales_ledger
GROUP BY
    1
ORDER BY
    year;






