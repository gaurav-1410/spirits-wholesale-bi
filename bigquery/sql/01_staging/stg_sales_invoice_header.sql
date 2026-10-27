-- Posted sales invoices (header)
CREATE OR REPLACE VIEW staging.stg_sales_invoice_header AS
SELECT
  TRIM(`No`)                                 AS invoice_no,
  TRIM(Sell_to_Customer_No)                AS customer_no,
  Posting_Date                             AS posting_date,
  Due_Date                                 AS due_date,
  NULLIF(TRIM(Payment_Terms_Code), '')     AS payment_terms_code,
  NULLIF(TRIM(Salesperson_Code), '')       AS salesperson_code,
  Shipment_Method_Code                     AS shipment_method_code,
  Order_No                                 AS sales_order_no,
  User_ID                                  AS posted_by_user,
  Amount                                   AS net_amount_eur,
  Amount_Including_VAT                     AS gross_amount_eur
FROM raw.sales_invoice_header;
