CREATE OR REPLACE VIEW staging.stg_salesperson AS
SELECT
  TRIM(Code)      AS salesperson_code,
  TRIM(Name)      AS salesperson_name,
  TRIM(Region)    AS sales_region,
  TRIM(Territory) AS territory,
  LOWER(E_Mail)   AS email,
  Start_Date      AS start_date
FROM raw.salesperson;
