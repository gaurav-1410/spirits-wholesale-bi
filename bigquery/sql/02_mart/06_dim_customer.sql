-- Customers with channel, region, lifecycle status and ABC class
CREATE OR REPLACE TABLE mart.dim_customer AS
WITH inv AS (
  SELECT
    customer_no,
    MIN(posting_date)  AS first_invoice_date,
    MAX(posting_date)  AS last_invoice_date,
    COUNT(*)           AS invoice_count
  FROM staging.stg_sales_invoice_header
  GROUP BY customer_no
),
l12m AS (
  SELECT h.customer_no, SUM(h.net_amount_eur) AS revenue_l12m
  FROM staging.stg_sales_invoice_header h
  CROSS JOIN mart.report_parameters p
  WHERE h.posting_date > DATE_SUB(p.report_date, INTERVAL 12 MONTH)
  GROUP BY h.customer_no
),
abc AS (
  SELECT
    customer_no,
    revenue_l12m,
    SUM(revenue_l12m) OVER (ORDER BY revenue_l12m DESC, customer_no
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      / SUM(revenue_l12m) OVER () AS cumulative_share
  FROM l12m
)
SELECT
  c.customer_no,
  c.customer_name,
  c.channel_code,
  CASE c.channel_code
    WHEN 'HORECA'    THEN 'Bars & Restaurants'
    WHEN 'RETAIL'    THEN 'Retail'
    WHEN 'WHOLESALE' THEN 'Wholesale'
    WHEN 'ONLINE'    THEN 'E-Commerce'
    ELSE 'Unknown'
  END                                                 AS channel_name,
  c.city,
  c.post_code,
  c.federal_state,
  CASE
    WHEN c.federal_state IN ('Bremen', 'Hamburg', 'Niedersachsen', 'Schleswig-Holstein',
                             'Mecklenburg-Vorpommern') THEN 'Nord'
    WHEN c.federal_state IN ('Nordrhein-Westfalen', 'Hessen', 'Rheinland-Pfalz', 'Saarland') THEN 'West'
    WHEN c.federal_state IN ('Bayern', 'Baden-Württemberg') THEN 'Süd'
    WHEN c.federal_state IN ('Berlin', 'Brandenburg', 'Sachsen', 'Sachsen-Anhalt', 'Thüringen') THEN 'Ost'
    ELSE 'Unknown'
  END                                                 AS customer_region,
  c.country_code,
  c.latitude,
  c.longitude,
  COALESCE(c.salesperson_code, 'UNASSIGNED')          AS salesperson_code,
  c.salesperson_code = 'IK'                           AS is_key_account,
  c.payment_terms_code,
  c.credit_limit_eur,
  c.is_blocked,
  c.blocked_date,
  c.created_date,
  i.first_invoice_date,
  i.last_invoice_date,
  COALESCE(i.invoice_count, 0)                        AS invoice_count,
  DATE_DIFF(p.report_date, i.last_invoice_date, DAY)  AS days_since_last_invoice,
  CASE
    WHEN c.is_blocked THEN 'Blocked'
    WHEN i.last_invoice_date IS NULL THEN 'No sales yet'
    WHEN DATE_DIFF(p.report_date, i.last_invoice_date, DAY) > 180 THEN 'Lost (> 180 days)'
    WHEN DATE_DIFF(p.report_date, i.last_invoice_date, DAY) > 90 THEN 'At risk (91–180 days)'
    WHEN i.first_invoice_date > DATE_SUB(p.report_date, INTERVAL 12 MONTH) THEN 'New (< 12 months)'
    ELSE 'Active'
  END                                                 AS customer_status,
  COALESCE(a.revenue_l12m, 0)                         AS revenue_l12m_eur,
  CASE
    WHEN a.revenue_l12m IS NULL OR a.revenue_l12m <= 0 THEN 'No sales L12M'
    WHEN a.cumulative_share <= 0.80 THEN 'A'
    WHEN a.cumulative_share <= 0.95 THEN 'B'
    ELSE 'C'
  END                                                 AS abc_class
FROM staging.stg_customer c
LEFT JOIN inv i USING (customer_no)
LEFT JOIN abc a USING (customer_no)
CROSS JOIN mart.report_parameters p;
