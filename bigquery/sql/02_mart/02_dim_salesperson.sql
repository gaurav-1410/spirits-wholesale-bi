-- Sales reps + an "unassigned" member so every fact row finds a dimension row
CREATE OR REPLACE TABLE mart.dim_salesperson AS
SELECT
  salesperson_code,
  salesperson_name,
  sales_region,
  territory,
  CASE salesperson_code
    WHEN 'IK' THEN 'Key Accounts'
    WHEN 'JS' THEN 'E-Commerce'
    ELSE 'Field Sales'
  END                AS sales_team,
  email,
  start_date
FROM staging.stg_salesperson
UNION ALL
SELECT 'UNASSIGNED', '(Unassigned)', 'Unknown', 'Unknown', 'Unknown', CAST(NULL AS STRING), CAST(NULL AS DATE);
