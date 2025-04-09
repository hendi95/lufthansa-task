------------ Query total sales per product category from the fact table.----------------
SELECT 
    p.product_category_name,
    SUM(f.total_price) AS total_sales
FROM 
    fact_order_items f
INNER JOIN 
    dim_products p
ON 
    f.product_id = p.product_id
GROUP BY 
    p.product_category_name
ORDER BY 
    total_sales DESC;


---------------------Query the average delivery time per seller from the fact table.-------------

SELECT 
    seller_id,
    AVG(delivery_time) AS avg_delivery_time
FROM 
    fact_order_items
GROUP BY 
    seller_id
ORDER BY 
    avg_delivery_time desc;


------------------Query the number of orders from each state from the customer dimension.--------------------
SELECT 
    c.customer_state,
    COUNT(f.order_id) AS number_of_orders
FROM 
    fact_order_items f
INNER JOIN 
    dim_customers c
ON 
    f.customer_id = c.customer_id
GROUP BY 
    c.customer_state
ORDER BY 
    number_of_orders DESC;

