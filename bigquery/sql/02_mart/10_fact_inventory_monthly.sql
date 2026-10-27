-- Month-end stock per item: quantity, value, movements, days of cover and stock health
CREATE OR REPLACE TABLE mart.fact_inventory_monthly AS
WITH months AS (
  SELECT DISTINCT d.month_end_date
  FROM mart.dim_date d
  CROSS JOIN mart.report_parameters p
  WHERE d.month_end_date BETWEEN DATE '2022-12-31' AND LAST_DAY(p.report_date, MONTH)
),
grid AS (
  SELECT i.item_no, m.month_end_date
  FROM staging.stg_item i
  CROSS JOIN months m
),
movements AS (
  SELECT
    item_no,
    GREATEST(LAST_DAY(posting_date, MONTH), DATE '2022-12-31')         AS month_end_date,
    SUM(quantity)                                                       AS net_qty,
    SUM(IF(entry_type = 'Purchase', quantity, 0))                       AS qty_received,
    SUM(IF(entry_type = 'Sale', -quantity, 0))                          AS qty_sold,
    SUM(IF(entry_type IN ('Positive Adjmt.', 'Negative Adjmt.')
           AND COALESCE(reason_code, '') <> 'OPENING', quantity, 0))   AS qty_adjusted
  FROM staging.stg_item_ledger_entry
  GROUP BY 1, 2
),
monthly_cost AS (
  SELECT item_no, LAST_DAY(posting_date, MONTH) AS month_end_date,
         SAFE_DIVIDE(SUM(cost_of_sales_eur), SUM(quantity_bottles)) AS avg_unit_cost
  FROM mart.fact_sales
  GROUP BY 1, 2
),
running AS (
  SELECT
    g.item_no,
    g.month_end_date,
    COALESCE(mv.qty_received, 0)  AS qty_received,
    COALESCE(mv.qty_sold, 0)      AS qty_sold,
    COALESCE(mv.qty_adjusted, 0)  AS qty_adjusted,
    SUM(COALESCE(mv.net_qty, 0)) OVER w_cum                                       AS closing_qty,
    COALESCE(LAST_VALUE(mc.avg_unit_cost IGNORE NULLS) OVER w_cum, i.unit_cost_eur) AS unit_cost_eur,
    AVG(COALESCE(mv.qty_sold, 0)) OVER (PARTITION BY g.item_no ORDER BY g.month_end_date
                                        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg_monthly_sold_3m,
    MAX(IF(COALESCE(mv.qty_sold, 0) > 0, g.month_end_date, NULL)) OVER w_cum      AS last_sale_month,
    i.created_date
  FROM grid g
  LEFT JOIN movements mv USING (item_no, month_end_date)
  LEFT JOIN monthly_cost mc USING (item_no, month_end_date)
  LEFT JOIN staging.stg_item i USING (item_no)
  WINDOW w_cum AS (PARTITION BY g.item_no ORDER BY g.month_end_date
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  item_no,
  month_end_date,
  qty_received,
  qty_sold,
  qty_adjusted,
  closing_qty,
  ROUND(unit_cost_eur, 4)                                        AS unit_cost_eur,
  ROUND(closing_qty * unit_cost_eur, 2)                          AS closing_value_eur,
  ROUND(avg_monthly_sold_3m, 2)                                  AS avg_monthly_sold_3m,
  ROUND(SAFE_DIVIDE(closing_qty, avg_monthly_sold_3m / 30.4), 1) AS days_of_cover,
  DATE_DIFF(month_end_date, last_sale_month, MONTH)              AS months_since_last_sale,
  CASE
    WHEN closing_qty < 0 THEN 'Negative stock'
    WHEN closing_qty = 0 THEN 'Out of stock'
    WHEN last_sale_month IS NULL OR DATE_DIFF(month_end_date, last_sale_month, MONTH) >= 6 THEN 'Dead stock (no sale 6M+)'
    WHEN SAFE_DIVIDE(closing_qty, avg_monthly_sold_3m / 30.4) > 180 THEN 'Slow moving (> 180 days cover)'
    WHEN SAFE_DIVIDE(closing_qty, avg_monthly_sold_3m / 30.4) > 90 THEN 'Excess (90–180 days cover)'
    ELSE 'Healthy'
  END                                                            AS stock_status
FROM running
WHERE month_end_date >= DATE '2023-01-31'
  AND (closing_qty <> 0 OR qty_sold <> 0 OR qty_received <> 0 OR created_date <= month_end_date);
