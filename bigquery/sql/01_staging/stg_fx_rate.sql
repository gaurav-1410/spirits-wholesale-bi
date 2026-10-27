-- FX rates: units of foreign currency per 1 EUR (ECB convention)
CREATE OR REPLACE VIEW staging.stg_fx_rate AS
SELECT
  Rate_Date                 AS rate_date,
  UPPER(TRIM(Currency_Code)) AS currency_code,
  Exchange_Rate             AS rate_per_eur
FROM raw.fx_rates_daily
WHERE Exchange_Rate > 0;
