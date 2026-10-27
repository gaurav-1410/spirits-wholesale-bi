-- Calendar dimension incl. Bremen public holidays and business-day flag
CREATE OR REPLACE TABLE mart.dim_date AS
WITH days AS (
  SELECT day AS date
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2022-12-01', DATE '2026-12-31')) AS day
)
SELECT
  d.date,
  CAST(FORMAT_DATE('%Y%m%d', d.date) AS INT64)                      AS date_key,
  EXTRACT(YEAR FROM d.date)                                         AS year,
  EXTRACT(QUARTER FROM d.date)                                      AS quarter,
  CONCAT(CAST(EXTRACT(YEAR FROM d.date) AS STRING), '-Q',
         CAST(EXTRACT(QUARTER FROM d.date) AS STRING))              AS year_quarter,
  EXTRACT(MONTH FROM d.date)                                        AS month,
  FORMAT_DATE('%b', d.date)                                         AS month_short,
  FORMAT_DATE('%Y-%m', d.date)                                      AS year_month,
  EXTRACT(YEAR FROM d.date) * 100 + EXTRACT(MONTH FROM d.date)      AS year_month_sort,
  DATE_TRUNC(d.date, MONTH)                                         AS month_start_date,
  LAST_DAY(d.date, MONTH)                                           AS month_end_date,
  EXTRACT(ISOYEAR FROM d.date)                                      AS iso_year,
  EXTRACT(ISOWEEK FROM d.date)                                      AS iso_week,
  MOD(EXTRACT(DAYOFWEEK FROM d.date) + 5, 7) + 1                    AS weekday_no,      -- 1 = Monday
  FORMAT_DATE('%a', d.date)                                         AS weekday_short,
  EXTRACT(DAYOFWEEK FROM d.date) IN (1, 7)                          AS is_weekend,
  h.holiday_name IS NOT NULL                                        AS is_public_holiday,
  h.holiday_name,
  EXTRACT(DAYOFWEEK FROM d.date) NOT IN (1, 7)
    AND h.holiday_name IS NULL                                      AS is_business_day,
  d.date <= p.report_date                                           AS is_actual_period,
  -- same day-of-year or earlier than the report date -> fair YTD vs. prior-YTD comparisons
  EXTRACT(DAYOFYEAR FROM d.date) <= EXTRACT(DAYOFYEAR FROM p.report_date) AS is_within_ytd
FROM days d
LEFT JOIN staging.stg_public_holiday h ON h.holiday_date = d.date
CROSS JOIN mart.report_parameters p;
