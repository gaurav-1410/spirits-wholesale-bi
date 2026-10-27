-- Sales fact at invoice-line grain: revenue, discounts, cost, margin, volume and excise duty
CREATE OR REPLACE TABLE mart.fact_sales AS
SELECT
  l.invoice_no,
  l.line_no,
  h.posting_date,
  h.customer_no,
  COALESCE(h.salesperson_code, 'UNASSIGNED')                       AS salesperson_code,
  IF(i.item_no IS NULL, 'UNKNOWN', l.item_no)                      AS item_no,
  l.item_no                                                        AS source_item_no,
  l.quantity                                                       AS quantity_bottles,
  l.unit_price_eur,
  l.discount_pct,
  ROUND(l.quantity * l.unit_price_eur, 2)                          AS gross_sales_eur,
  l.discount_amount_eur,
  l.net_amount_eur                                                 AS net_sales_eur,
  l.unit_cost_eur,
  ROUND(l.quantity * l.unit_cost_eur, 2)                           AS cost_of_sales_eur,
  l.net_amount_eur - ROUND(l.quantity * l.unit_cost_eur, 2)        AS gross_margin_eur,
  l.quantity * i.bottle_size_l                                     AS volume_l,
  l.quantity * i.pure_alcohol_l_per_bottle                         AS pure_alcohol_l,
  -- excise duty contained in the (duty-paid) cost of goods
  ROUND(l.quantity * i.pure_alcohol_l_per_bottle * e.rate_eur_per_l_pure_alcohol, 2) AS excise_duty_eur
FROM staging.stg_sales_invoice_line l
JOIN staging.stg_sales_invoice_header h USING (invoice_no)
LEFT JOIN staging.stg_item i USING (item_no)
LEFT JOIN staging.stg_excise_rate e
  ON h.posting_date BETWEEN e.valid_from AND e.valid_to AND e.product_group = 'SPIRITS';
