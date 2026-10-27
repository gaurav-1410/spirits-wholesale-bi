-- Items (bottles): standardised, with pure alcohol per bottle for excise calculations
CREATE OR REPLACE VIEW staging.stg_item AS
SELECT
  TRIM(`No`)                                     AS item_no,
  TRIM(Description)                            AS item_description,
  NULLIF(UPPER(TRIM(Item_Category_Code)), '')  AS item_category_code,
  TRIM(Brand)                                  AS brand,
  TRIM(Vendor_No)                              AS vendor_no,
  Base_Unit_of_Measure                         AS base_unit_of_measure,
  Bottle_Size_L                                AS bottle_size_l,
  Alcohol_Pct                                  AS alcohol_pct,
  Bottle_Size_L * Alcohol_Pct / 100            AS pure_alcohol_l_per_bottle,
  Country_of_Origin                            AS country_of_origin,
  Unit_Price                                   AS list_price_eur,
  Unit_Cost                                    AS unit_cost_eur,
  COALESCE(Blocked, FALSE)                     AS is_blocked,
  Blocked_Date                                 AS blocked_date,
  Created_Date                                 AS created_date
FROM raw.item;
