-- One FX rate per calendar day and currency. Weekends/holidays carry the last ECB rate forward.
CREATE OR REPLACE TABLE mart.fx_rate_daily AS
WITH grid AS (
  SELECT d.date AS rate_date, c.currency_code
  FROM mart.dim_date d
  CROSS JOIN (SELECT DISTINCT currency_code FROM staging.stg_fx_rate) c
),
filled AS (
  SELECT
    g.rate_date,
    g.currency_code,
    LAST_VALUE(f.rate_per_eur IGNORE NULLS) OVER (
      PARTITION BY g.currency_code ORDER BY g.rate_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)  AS rate_per_eur,
    f.rate_per_eur IS NULL                                AS is_carried_forward
  FROM grid g
  LEFT JOIN staging.stg_fx_rate f
    ON f.rate_date = g.rate_date AND f.currency_code = g.currency_code
)
SELECT rate_date, currency_code, rate_per_eur, is_carried_forward FROM filled
UNION ALL
SELECT d.date, 'EUR', 1.0, FALSE FROM mart.dim_date d;
