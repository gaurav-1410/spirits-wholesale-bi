-- Customers: trimmed, standardised, with a normalised name key for duplicate detection
CREATE OR REPLACE VIEW staging.stg_customer AS
SELECT
  TRIM(`No`)                                              AS customer_no,
  REGEXP_REPLACE(TRIM(Name), r'\s+', ' ')               AS customer_name,
  -- lower-case, single spaces, legal form removed -> "Bar Anker GmbH" = "BAR  ANKER"
  REGEXP_REPLACE(LOWER(REGEXP_REPLACE(TRIM(Name), r'\s+', ' ')), r' (gmbh|kg|e\.k\.)$', '')
                                                        AS customer_name_key,
  NULLIF(TRIM(Post_Code), '')                           AS post_code,
  TRIM(City)                                            AS city,
  TRIM(County)                                          AS federal_state,
  Country_Region_Code                                   AS country_code,
  Latitude                                              AS latitude,
  Longitude                                             AS longitude,
  UPPER(TRIM(Customer_Price_Group))                     AS channel_code,
  NULLIF(TRIM(Salesperson_Code), '')                    AS salesperson_code,
  NULLIF(TRIM(Payment_Terms_Code), '')                  AS payment_terms_code,
  Credit_Limit_LCY                                      AS credit_limit_eur,
  COALESCE(TRIM(Blocked), '') = 'All'                   AS is_blocked,
  Blocked_Date                                          AS blocked_date,
  Created_Date                                          AS created_date
FROM raw.customer;
