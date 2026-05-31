-- ================================================
-- PROJECT: Olist E-Commerce Customer Analytics
-- TOOL: MySQL
-- DATASET: Brazilian E-Commerce (Kaggle/Olist)
-- ANALYST: Sachin Malee
-- ================================================

USE olist_ecommerce;

-- =================================================
-- BUSINESS PROBLEM 1: Overall Business Health Check
-- =================================================
SELECT
    COUNT(DISTINCT o.order_id)          AS total_orders,
    COUNT(DISTINCT o.customer_id)       AS total_customers,
    COUNT(DISTINCT oi.seller_id)        AS total_sellers,
    COUNT(DISTINCT oi.product_id)       AS total_products,
    ROUND(SUM(p.payment_value), 2)      AS total_revenue,
    ROUND(AVG(p.payment_value), 2)      AS avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN payments p     ON o.order_id = p.order_id
WHERE o.order_status = 'delivered';

-- ==================================================
-- BUSINESS PROBLEM 2: Monthly Revenue Trend + Growth
-- ==================================================
WITH monthly_rev AS (
    SELECT
        YEAR(o.order_purchase_timestamp)    AS yr,
        MONTH(o.order_purchase_timestamp)   AS mn,
        DATE_FORMAT(o.order_purchase_timestamp,
            '%Y-%m')                        AS years_month,
        COUNT(DISTINCT o.order_id)          AS total_orders,
        ROUND(SUM(p.payment_value), 2)      AS revenue
    FROM orders o
    JOIN payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY yr, mn, years_month
)
SELECT
    years_month,
    total_orders,
    revenue,
    LAG(revenue) OVER (
        ORDER BY yr, mn)                    AS prev_revenue,
    ROUND((revenue -
        LAG(revenue) OVER (ORDER BY yr, mn))
        / LAG(revenue) OVER (ORDER BY yr, mn)
        * 100, 2)                           AS mom_growth_pct,
    SUM(revenue) OVER (
        ORDER BY yr, mn
        ROWS BETWEEN UNBOUNDED PRECEDING
        AND CURRENT ROW)                    AS cumulative_revenue
FROM monthly_rev
ORDER BY yr, mn;

-- ========================================================
-- BUSINESS PROBLEM 3: Top 10 Product Categories by Revenue
-- ========================================================
SELECT
    COALESCE(t.product_category_name_english,
             p.product_category_name,
             'Unknown')                     AS category,
    COUNT(DISTINCT oi.order_id)             AS total_orders,
    ROUND(SUM(oi.price), 2)                 AS revenue,
    ROUND(AVG(oi.price), 2)                 AS avg_price,
    RANK() OVER (
        ORDER BY SUM(oi.price) DESC)        AS revenue_rank
FROM order_items oi
JOIN products p     ON oi.product_id = p.product_id
JOIN orders o       ON oi.order_id   = o.order_id
LEFT JOIN translation t
    ON p.product_category_name =
       t.product_category_name
WHERE o.order_status = 'delivered'
  AND p.product_category_name IS NOT NULL
GROUP BY category
ORDER BY revenue DESC
LIMIT 10;

-- ================================================
-- BUSINESS PROBLEM 4: Customer Segmentation — RFM
-- ================================================
WITH rfm_base AS (
    SELECT
        c.customer_unique_id,
        DATEDIFF('2018-10-17',
            MAX(DATE(o.order_purchase_timestamp)))
                                            AS recency_days,
        COUNT(DISTINCT o.order_id)          AS frequency,
        ROUND(SUM(p.payment_value), 2)      AS monetary
    FROM customers c
    JOIN orders o   ON c.customer_id  = o.customer_id
    JOIN payments p ON o.order_id     = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT *,
        NTILE(5) OVER (
            ORDER BY recency_days DESC)     AS r_score,
        NTILE(5) OVER (
            ORDER BY frequency ASC)        AS f_score,
        NTILE(5) OVER (
            ORDER BY monetary ASC)         AS m_score
    FROM rfm_base
)
SELECT *,
    ROUND((r_score + f_score + m_score)
        / 3.0, 1)                          AS rfm_avg,
    CASE
        WHEN ROUND((r_score + f_score +
             m_score)/3.0,1) >= 4.5
             THEN 'Champion'
        WHEN ROUND((r_score + f_score +
             m_score)/3.0,1) >= 3.5
             THEN 'Loyal Customer'
        WHEN ROUND((r_score + f_score +
             m_score)/3.0,1) >= 2.5
             THEN 'Potential Loyal'
        WHEN ROUND((r_score + f_score +
             m_score)/3.0,1) >= 1.5
             THEN 'At Risk'
        ELSE 'Lost Customer'
    END                                    AS rfm_segment
FROM rfm_scored
ORDER BY rfm_avg DESC;

-- ==================================================
-- BUSINESS PROBLEM 5: Delivery Performance Analysis
-- ==================================================
SELECT
    COUNT(*)                               AS total_delivered,
    ROUND(AVG(DATEDIFF(
        order_delivered_customer_date,
        order_purchase_timestamp)), 1)     AS avg_delivery_days,
    ROUND(AVG(DATEDIFF(
        order_estimated_delivery_date,
        order_purchase_timestamp)), 1)     AS avg_estimated_days,
    SUM(CASE
        WHEN order_delivered_customer_date
           <= order_estimated_delivery_date
        THEN 1 ELSE 0 END)                 AS on_time_orders,
    SUM(CASE
        WHEN order_delivered_customer_date
           > order_estimated_delivery_date
        THEN 1 ELSE 0 END)                 AS late_orders,
    ROUND(SUM(CASE
        WHEN order_delivered_customer_date
           <= order_estimated_delivery_date
        THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 2)                     AS on_time_rate_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date
      IS NOT NULL;
      
-- ================================================
-- BUSINESS PROBLEM 6: Review Score Analysis
-- ================================================
SELECT
    r.review_score,
    COUNT(*)                               AS total_reviews,
    ROUND(COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER(), 2)           AS percentage,
    ROUND(AVG(p.payment_value), 2)         AS avg_order_value
FROM reviews r
JOIN orders o   ON r.order_id = o.order_id
JOIN payments p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY r.review_score
ORDER BY r.review_score DESC;

-- ================================================
-- BUSINESS PROBLEM 7: Top 10 Sellers by Revenue
-- ================================================
WITH seller_stats AS (
    SELECT
        oi.seller_id,
        s.seller_city,
        s.seller_state,
        COUNT(DISTINCT oi.order_id)        AS total_orders,
        ROUND(SUM(oi.price), 2)            AS revenue,
        ROUND(AVG(r.review_score), 2)      AS avg_rating
    FROM order_items oi
    JOIN sellers s  ON oi.seller_id  = s.seller_id
    JOIN orders o   ON oi.order_id   = o.order_id
    LEFT JOIN reviews r ON oi.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id,
             s.seller_city,
             s.seller_state
)
SELECT *,
    RANK() OVER (
        ORDER BY revenue DESC)             AS rank_num
FROM seller_stats
ORDER BY revenue DESC
LIMIT 10;

-- ================================================
-- BUSINESS PROBLEM 8: Payment Type Analysis
-- ================================================
SELECT
    payment_type,
    COUNT(DISTINCT order_id)               AS total_orders,
    ROUND(SUM(payment_value), 2)           AS total_revenue,
    ROUND(AVG(payment_value), 2)           AS avg_order_value,
    ROUND(AVG(payment_installments), 1)    AS avg_installments,
    ROUND(COUNT(DISTINCT order_id) * 100.0
        / SUM(COUNT(DISTINCT order_id))
        OVER(), 2)                         AS usage_pct
FROM payments
GROUP BY payment_type
ORDER BY total_revenue DESC;

-- ================================================
-- BUSINESS PROBLEM 9: State wise Performance
-- ================================================
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)             AS total_orders,
    COUNT(DISTINCT c.customer_unique_id)   AS unique_customers,
    ROUND(SUM(p.payment_value), 2)         AS total_revenue,
    ROUND(AVG(p.payment_value), 2)         AS avg_order_value,
    RANK() OVER (
        ORDER BY SUM(p.payment_value) DESC) AS revenue_rank
FROM customers c
JOIN orders o   ON c.customer_id = o.customer_id
JOIN payments p ON o.order_id    = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY total_revenue DESC;

-- ================================================
-- BUSINESS PROBLEM 10: Repeat vs One-Time Buyers
-- ================================================
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id)         AS total_orders,
        ROUND(SUM(p.payment_value), 2)     AS lifetime_value
    FROM customers c
    JOIN orders o   ON c.customer_id = o.customer_id
    JOIN payments p ON o.order_id    = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    CASE
        WHEN total_orders = 1  THEN 'One-Time Buyer'
        WHEN total_orders = 2  THEN 'Returning Buyer'
        WHEN total_orders <= 5 THEN 'Regular (3-5)'
        ELSE                        'VIP (5+)'
    END                                    AS customer_type,
    COUNT(*)                               AS customer_count,
    ROUND(AVG(lifetime_value), 2)          AS avg_ltv,
    ROUND(SUM(lifetime_value), 2)          AS total_revenue,
    ROUND(COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER(), 2)           AS customer_pct
FROM customer_orders
GROUP BY customer_type
ORDER BY avg_ltv DESC;


