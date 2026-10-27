-- Single-row table with the reporting cut-off ("as of" date) used by all marts and checks
CREATE OR REPLACE TABLE mart.report_parameters AS
SELECT
  MAX(posting_date)                           AS report_date,
  DATE '2023-01-01'                           AS data_start_date,
  'Hanse Spirits Trading GmbH (fictional)'    AS company_name,
  25.0                                        AS max_discount_pct_policy,
  50000                                       AS po_cfo_approval_threshold_eur,
  'RBRANDT'                                   AS cfo_user_id
FROM staging.stg_sales_invoice_header
WHERE posting_date <= CURRENT_DATE();
