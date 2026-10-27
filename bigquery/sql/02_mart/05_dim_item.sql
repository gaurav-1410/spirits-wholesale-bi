-- Items with vendor attributes, lifecycle status and ABC class (last 12 months net revenue)
CREATE OR REPLACE TABLE mart.dim_item AS
WITH l12m AS (
  SELECT l.item_no, SUM(l.net_amount_eur) AS revenue_l12m
  FROM staging.stg_sales_invoice_line l
  JOIN staging.stg_sales_invoice_header h USING (invoice_no)
  CROSS JOIN mart.report_parameters p
  WHERE h.posting_date > DATE_SUB(p.report_date, INTERVAL 12 MONTH)
  GROUP BY l.item_no
),
abc AS (
  SELECT
    item_no,
    revenue_l12m,
    SUM(revenue_l12m) OVER (ORDER BY revenue_l12m DESC, item_no
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      / SUM(revenue_l12m) OVER ()                                      AS cumulative_share
  FROM l12m
)
SELECT
  i.item_no,
  i.item_description,
  COALESCE(i.item_category_code, 'UNASSIGNED')   AS item_category_code,
  i.brand,
  i.vendor_no,
  v.vendor_name,
  v.country_code                                 AS vendor_country_code,
  v.currency_code                                AS purchase_currency,
  i.country_of_origin,
  i.bottle_size_l,
  i.alcohol_pct,
  i.pure_alcohol_l_per_bottle,
  CASE
    WHEN i.alcohol_pct >= 50 THEN 'High proof (50 %+)'
    WHEN i.alcohol_pct >= 37.5 THEN 'Standard (37.5–49 %)'
    ELSE 'Liqueur strength (< 37.5 %)'
  END                                            AS strength_band,
  i.list_price_eur,
  CASE
    WHEN i.list_price_eur < 15 THEN '1 Value (< 15 €)'
    WHEN i.list_price_eur < 30 THEN '2 Standard (15–30 €)'
    WHEN i.list_price_eur < 60 THEN '3 Premium (30–60 €)'
    ELSE '4 Super premium (60 € +)'
  END                                            AS price_segment,
  i.unit_cost_eur,
  i.is_blocked,
  i.blocked_date,
  i.created_date,
  CASE
    WHEN i.is_blocked THEN 'Discontinued'
    WHEN i.created_date > DATE_SUB(p.report_date, INTERVAL 12 MONTH) THEN 'New (< 12 months)'
    ELSE 'Active'
  END                                            AS item_status,
  COALESCE(a.revenue_l12m, 0)                    AS revenue_l12m_eur,
  CASE
    WHEN a.revenue_l12m IS NULL OR a.revenue_l12m <= 0 THEN 'No sales L12M'
    WHEN a.cumulative_share <= 0.80 THEN 'A'
    WHEN a.cumulative_share <= 0.95 THEN 'B'
    ELSE 'C'
  END                                            AS abc_class
FROM staging.stg_item i
LEFT JOIN staging.stg_vendor v USING (vendor_no)
LEFT JOIN abc a USING (item_no)
CROSS JOIN mart.report_parameters p

UNION ALL
-- "unknown" member for invoice lines whose item number is missing in the item master
SELECT
  'UNKNOWN', '(Unknown item)', 'UNASSIGNED', '(Unknown)', CAST(NULL AS STRING), '(Unknown)',
  CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING),
  CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), '(Unknown)',
  CAST(NULL AS NUMERIC), '(Unknown)', CAST(NULL AS NUMERIC), FALSE, CAST(NULL AS DATE), CAST(NULL AS DATE),
  '(Unknown)', CAST(0 AS NUMERIC), 'No sales L12M';
