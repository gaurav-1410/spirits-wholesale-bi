-- Public holidays valid in Bremen (company location); one row per date
CREATE OR REPLACE VIEW staging.stg_public_holiday AS
SELECT
  Holiday_Date                      AS holiday_date,
  STRING_AGG(Holiday_Name, ' / ')   AS holiday_name
FROM raw.public_holidays_de_hb
GROUP BY Holiday_Date;
