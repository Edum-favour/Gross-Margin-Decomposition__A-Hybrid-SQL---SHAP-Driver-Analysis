-- prepare transaction-level revenue and cost metrics for downstream analysis

SELECT 
    transaction_id,
    order_id,
    transaction_date,
    product_id,
    quantity,
    unit_price,
    discount_rate,
    unit_cost,
    (quantity * unit_price * (1 - discount_rate)) AS net_revenue,
    quantity * unit_cost AS cogs
FROM
    transactions;





