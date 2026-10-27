CREATE OR REPLACE TABLE mart.dim_vendor AS
SELECT
  vendor_no,
  vendor_name,
  country_code,
  CASE
    WHEN country_code = 'DE' THEN 'Germany'
    WHEN country_code IN ('GB', 'IE', 'FR', 'IT', 'ES', 'PL', 'SE', 'FI', 'LT') THEN 'Europe'
    WHEN country_code = 'US' THEN 'USA'
    ELSE 'Caribbean & Latin America'
  END                       AS sourcing_region,
  currency_code,
  currency_code <> 'EUR'    AS is_foreign_currency,
  payment_terms_code,
  lead_time_days,
  vendor_posting_group
FROM staging.stg_vendor;
