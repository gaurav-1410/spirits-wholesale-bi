-- Posted sales invoice lines (item lines only)
CREATE OR REPLACE VIEW staging.stg_sales_invoice_line AS
SELECT
  TRIM(Document_No)      AS invoice_no,
  Line_No                AS line_no,
  TRIM(`No`)               AS item_no,
  Quantity               AS quantity,
  Unit_Price             AS unit_price_eur,
  Line_Discount_Pct      AS discount_pct,
  Line_Discount_Amount   AS discount_amount_eur,
  Amount                 AS net_amount_eur,
  Amount_Including_VAT   AS gross_amount_eur,
  Unit_Cost_LCY          AS unit_cost_eur
FROM raw.sales_invoice_line
WHERE Type = 'Item';
