-- Vendors: empty currency code means local currency (EUR) in Business Central
CREATE OR REPLACE VIEW staging.stg_vendor AS
SELECT
  TRIM(`No`)                                         AS vendor_no,
  TRIM(Name)                                       AS vendor_name,
  Country_Region_Code                              AS country_code,
  COALESCE(NULLIF(TRIM(Currency_Code), ''), 'EUR') AS currency_code,
  NULLIF(TRIM(Payment_Terms_Code), '')             AS payment_terms_code,
  Lead_Time_Days                                   AS lead_time_days,
  Vendor_Posting_Group                             AS vendor_posting_group,
  COALESCE(Blocked, FALSE)                         AS is_blocked
FROM raw.vendor;
