-- All control exceptions in one table (one row = one finding) for the Power BI controls page
CREATE OR REPLACE TABLE dq.exceptions AS
WITH p AS (SELECT * FROM mart.report_parameters),

c01 AS (
  SELECT 'C01' AS check_id, 'Invoice line' AS entity_type,
         CONCAT(invoice_no, '/', CAST(line_no AS STRING)) AS entity_id, invoice_no AS document_no,
         posting_date AS event_date, customer_no, CAST(NULL AS STRING) AS vendor_no, item_no, salesperson_code,
         CAST(cost_of_sales_eur - net_sales_eur AS FLOAT64) AS impact_eur,
         FORMAT('Net price %.2f EUR below unit cost %.2f EUR',
                CAST(net_sales_eur / quantity_bottles AS FLOAT64), CAST(unit_cost_eur AS FLOAT64)) AS detail
  FROM mart.fact_sales
  WHERE quantity_bottles > 0 AND net_sales_eur < cost_of_sales_eur
),
c02 AS (
  SELECT 'C02', 'Invoice line', CONCAT(f.invoice_no, '/', CAST(f.line_no AS STRING)), f.invoice_no,
         f.posting_date, f.customer_no, CAST(NULL AS STRING), f.item_no, f.salesperson_code,
         CAST(f.discount_amount_eur AS FLOAT64),
         FORMAT('Discount %.0f %% (policy max. %.0f %%)', CAST(f.discount_pct AS FLOAT64), p.max_discount_pct_policy)
  FROM mart.fact_sales f CROSS JOIN p
  WHERE f.discount_pct > p.max_discount_pct_policy
),
inv AS (
  SELECT
    invoice_no, customer_no, posting_date, net_amount_eur, salesperson_code,
    ROW_NUMBER()  OVER (PARTITION BY customer_no, posting_date, net_amount_eur ORDER BY invoice_no) AS rn,
    FIRST_VALUE(invoice_no) OVER (PARTITION BY customer_no, posting_date, net_amount_eur ORDER BY invoice_no) AS first_invoice_no
  FROM staging.stg_sales_invoice_header
),
c03 AS (
  SELECT 'C03', 'Invoice', invoice_no, invoice_no, posting_date, customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(salesperson_code, 'UNASSIGNED'), CAST(net_amount_eur AS FLOAT64),
         CONCAT('Same customer, date and amount as ', first_invoice_no)
  FROM inv WHERE rn > 1
),
c04 AS (
  SELECT 'C04', 'Invoice', h.invoice_no, h.invoice_no, h.posting_date, h.customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(h.salesperson_code, 'UNASSIGNED'), CAST(h.net_amount_eur AS FLOAT64),
         CONCAT('Customer blocked since ', CAST(c.blocked_date AS STRING))
  FROM staging.stg_sales_invoice_header h
  JOIN staging.stg_customer c USING (customer_no)
  WHERE c.is_blocked AND h.posting_date >= c.blocked_date
),
c05 AS (
  SELECT 'C05', 'Invoice', h.invoice_no, h.invoice_no, h.posting_date, h.customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(h.salesperson_code, 'UNASSIGNED'), CAST(h.net_amount_eur AS FLOAT64),
         CONCAT('Posted on ', d.weekday_short, COALESCE(CONCAT(' (', d.holiday_name, ')'), ''),
                ' by user ', h.posted_by_user)
  FROM staging.stg_sales_invoice_header h
  JOIN mart.dim_date d ON d.date = h.posting_date
  WHERE NOT d.is_business_day
),
c06 AS (
  SELECT 'C06', 'Invoice line', CONCAT(invoice_no, '/', CAST(line_no AS STRING)), invoice_no, posting_date,
         customer_no, CAST(NULL AS STRING), source_item_no, salesperson_code, CAST(net_sales_eur AS FLOAT64),
         CONCAT('Item ', source_item_no, ' not found in item master')
  FROM mart.fact_sales
  WHERE item_no = 'UNKNOWN'
),
open_ar AS (
  SELECT customer_no, SUM(open_amount_eur) AS open_amount_eur
  FROM mart.fact_receivables WHERE is_open GROUP BY customer_no
),
c07 AS (
  SELECT 'C07', 'Customer', c.customer_no, CAST(NULL AS STRING), p.report_date, c.customer_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), c.salesperson_code,
         CAST(o.open_amount_eur - c.credit_limit_eur AS FLOAT64),
         FORMAT('Open %.0f EUR vs. limit %.0f EUR', CAST(o.open_amount_eur AS FLOAT64),
                CAST(c.credit_limit_eur AS FLOAT64))
  FROM mart.dim_customer c JOIN open_ar o USING (customer_no) CROSS JOIN p
  WHERE o.open_amount_eur > c.credit_limit_eur
),
c08 AS (
  SELECT 'C08', 'Invoice', invoice_no, invoice_no, due_date, customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), salesperson_code, CAST(open_amount_eur AS FLOAT64),
         CONCAT(CAST(days_overdue AS STRING), ' days overdue')
  FROM mart.fact_receivables
  WHERE is_open AND days_overdue > 90
),
po AS (
  SELECT po_no, ANY_VALUE(vendor_no) AS vendor_no, ANY_VALUE(order_date) AS order_date,
         ANY_VALUE(created_by) AS created_by, ANY_VALUE(approved_by) AS approved_by,
         SUM(order_amount_eur) AS po_amount_eur
  FROM mart.fact_purchase GROUP BY po_no
),
c09 AS (
  SELECT 'C09', 'Purchase order', po_no, po_no, order_date, CAST(NULL AS STRING), vendor_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(po_amount_eur AS FLOAT64),
         CONCAT('Created and approved by ', created_by)
  FROM po WHERE created_by = approved_by
),
c10 AS (
  SELECT 'C10', 'Purchase order', po_no, po_no, order_date, CAST(NULL AS STRING), vendor_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(po_amount_eur AS FLOAT64),
         CONCAT('No approver; created by ', created_by)
  FROM po WHERE approved_by IS NULL
),
c11 AS (
  SELECT 'C11', 'Purchase order', po.po_no, po.po_no, po.order_date, CAST(NULL AS STRING), po.vendor_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(po.po_amount_eur AS FLOAT64),
         FORMAT('%.0f EUR approved by %s (CFO required)', CAST(po.po_amount_eur AS FLOAT64), po.approved_by)
  FROM po CROSS JOIN p
  WHERE po.po_amount_eur >= p.po_cfo_approval_threshold_eur
    AND po.approved_by IS NOT NULL AND po.approved_by <> p.cfo_user_id AND po.approved_by <> po.created_by
),
c12 AS (
  SELECT 'C12', 'Item ledger entry', CAST(e.entry_no AS STRING), e.document_no, e.posting_date,
         CAST(NULL AS STRING), CAST(NULL AS STRING), e.item_no, CAST(NULL AS STRING),
         CAST(ABS(e.quantity) * i.unit_cost_eur AS FLOAT64),
         FORMAT('%s of %.0f bottles without reason code', e.entry_type, CAST(e.quantity AS FLOAT64))
  FROM staging.stg_item_ledger_entry e
  LEFT JOIN staging.stg_item i USING (item_no)
  WHERE e.entry_type IN ('Positive Adjmt.', 'Negative Adjmt.')
    AND ABS(e.quantity) >= 24 AND e.reason_code IS NULL
),
c13 AS (
  SELECT 'C13', 'Item stock (month end)', CONCAT(item_no, '@', CAST(month_end_date AS STRING)), CAST(NULL AS STRING),
         month_end_date, CAST(NULL AS STRING), CAST(NULL AS STRING), item_no, CAST(NULL AS STRING),
         CAST(ABS(closing_value_eur) AS FLOAT64),
         FORMAT('Closing stock %.0f bottles', CAST(closing_qty AS FLOAT64))
  FROM mart.fact_inventory_monthly
  WHERE closing_qty < 0
),
c14 AS (
  SELECT 'C14', 'Customer', customer_no, CAST(NULL AS STRING), created_date, customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(salesperson_code, 'UNASSIGNED'), CAST(0 AS FLOAT64),
         ARRAY_TO_STRING([IF(salesperson_code IS NULL, 'salesperson missing', NULL),
                          IF(post_code IS NULL, 'post code missing', NULL)], ', ')
  FROM staging.stg_customer
  WHERE salesperson_code IS NULL OR post_code IS NULL
  UNION ALL
  SELECT 'C14', 'Item', item_no, CAST(NULL AS STRING), created_date, CAST(NULL AS STRING), vendor_no, item_no,
         CAST(NULL AS STRING), CAST(0 AS FLOAT64), 'item category missing'
  FROM staging.stg_item WHERE item_category_code IS NULL
  UNION ALL
  SELECT 'C14', 'Vendor', vendor_no, CAST(NULL AS STRING), CAST(NULL AS DATE), CAST(NULL AS STRING), vendor_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(0 AS FLOAT64), 'payment terms missing'
  FROM staging.stg_vendor WHERE payment_terms_code IS NULL
),
dup_cust AS (
  SELECT
    customer_no, customer_name, post_code, created_date, salesperson_code,
    ROW_NUMBER()  OVER (PARTITION BY customer_name_key, post_code ORDER BY created_date, customer_no) AS rn,
    FIRST_VALUE(customer_no) OVER (PARTITION BY customer_name_key, post_code ORDER BY created_date, customer_no) AS original_no
  FROM staging.stg_customer
),
c15 AS (
  SELECT 'C15', 'Customer', customer_no, CAST(NULL AS STRING), created_date, customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(salesperson_code, 'UNASSIGNED'), CAST(0 AS FLOAT64),
         CONCAT('"', customer_name, '" looks like a duplicate of ', original_no)
  FROM dup_cust WHERE rn > 1
),
all_exceptions AS (
  SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03 UNION ALL
  SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06 UNION ALL
  SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09 UNION ALL
  SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12 UNION ALL
  SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
)
SELECT
  CONCAT(a.check_id, '|', a.entity_id) AS exception_id,
  a.*,
  ROUND(a.impact_eur, 2)               AS impact_eur_rounded,
  c.check_name,
  c.control_area,
  c.risk_level,
  c.control_owner,
  CURRENT_TIMESTAMP()                  AS checked_at
FROM all_exceptions a
JOIN dq.check_catalog c USING (check_id);
