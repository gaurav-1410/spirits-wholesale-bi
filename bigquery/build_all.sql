-- ---------- 01_staging/stg_cust_ledger_entry.sql ----------
-- Customer ledger entries (receivables): one entry per invoice, amounts incl. VAT
CREATE OR REPLACE VIEW staging.stg_cust_ledger_entry AS
SELECT
  Entry_No              AS entry_no,
  TRIM(Customer_No)     AS customer_no,
  Posting_Date          AS posting_date,
  Document_Type         AS document_type,
  TRIM(Document_No)     AS invoice_no,
  Amount_LCY            AS amount_eur,
  Remaining_Amt_LCY     AS remaining_amount_eur,
  Due_Date              AS due_date,
  Open                  AS is_open,
  Closed_at_Date        AS closed_at_date,
  NULLIF(TRIM(Salesperson_Code), '') AS salesperson_code
FROM raw.cust_ledger_entry;

-- ---------- 01_staging/stg_customer.sql ----------
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

-- ---------- 01_staging/stg_excise_rate.sql ----------
-- German spirits excise duty (Alkoholsteuer), converted to EUR per litre of pure alcohol
CREATE OR REPLACE VIEW staging.stg_excise_rate AS
SELECT
  Product_Group                                AS product_group,
  Valid_From                                   AS valid_from,
  COALESCE(Valid_To, DATE '9999-12-31')        AS valid_to,
  Rate_EUR_per_hl_pure_alcohol / 100           AS rate_eur_per_l_pure_alcohol,
  Legal_Basis                                  AS legal_basis
FROM raw.excise_duty_rates;

-- ---------- 01_staging/stg_fx_rate.sql ----------
-- FX rates: units of foreign currency per 1 EUR (ECB convention)
CREATE OR REPLACE VIEW staging.stg_fx_rate AS
SELECT
  Rate_Date                 AS rate_date,
  UPPER(TRIM(Currency_Code)) AS currency_code,
  Exchange_Rate             AS rate_per_eur
FROM raw.fx_rates_daily
WHERE Exchange_Rate > 0;

-- ---------- 01_staging/stg_item.sql ----------
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

-- ---------- 01_staging/stg_item_ledger_entry.sql ----------
-- Item ledger entries = every stock movement (receipt, sale, adjustment)
CREATE OR REPLACE VIEW staging.stg_item_ledger_entry AS
SELECT
  Entry_No                           AS entry_no,
  TRIM(Item_No)                      AS item_no,
  Posting_Date                       AS posting_date,
  Entry_Type                         AS entry_type,
  NULLIF(TRIM(Document_Type), '')    AS document_type,
  TRIM(Document_No)                  AS document_no,
  NULLIF(TRIM(Order_No), '')         AS order_no,
  Location_Code                      AS location_code,
  Quantity                           AS quantity,
  NULLIF(TRIM(Reason_Code), '')      AS reason_code
FROM raw.item_ledger_entry;

-- ---------- 01_staging/stg_public_holiday.sql ----------
-- Public holidays valid in Bremen (company location); one row per date
CREATE OR REPLACE VIEW staging.stg_public_holiday AS
SELECT
  Holiday_Date                      AS holiday_date,
  STRING_AGG(Holiday_Name, ' / ')   AS holiday_name
FROM raw.public_holidays_de_hb
GROUP BY Holiday_Date;

-- ---------- 01_staging/stg_purchase_header.sql ----------
-- Purchase orders (header) incl. approval information for ICS checks
CREATE OR REPLACE VIEW staging.stg_purchase_header AS
SELECT
  TRIM(`No`)                                         AS po_no,
  TRIM(Buy_from_Vendor_No)                         AS vendor_no,
  Order_Date                                       AS order_date,
  Expected_Receipt_Date                            AS expected_receipt_date,
  COALESCE(NULLIF(TRIM(Currency_Code), ''), 'EUR') AS currency_code,
  Shipment_Method_Code                             AS shipment_method_code,
  Status                                           AS status,
  NULLIF(TRIM(Created_By), '')                     AS created_by,
  NULLIF(TRIM(Approved_By), '')                    AS approved_by,
  Approval_Date                                    AS approval_date
FROM raw.purchase_header;

-- ---------- 01_staging/stg_purchase_line.sql ----------
-- Purchase order lines; costs are in the vendor's currency (fc = foreign currency)
CREATE OR REPLACE VIEW staging.stg_purchase_line AS
SELECT
  TRIM(Document_No)       AS po_no,
  Line_No                 AS line_no,
  TRIM(`No`)                AS item_no,
  Quantity                AS quantity,
  Quantity_Received       AS quantity_received,
  Direct_Unit_Cost        AS direct_unit_cost_fc,
  Line_Amount             AS line_amount_fc,
  Expected_Receipt_Date   AS expected_receipt_date
FROM raw.purchase_line
WHERE Type = 'Item';

-- ---------- 01_staging/stg_sales_invoice_header.sql ----------
-- Posted sales invoices (header)
CREATE OR REPLACE VIEW staging.stg_sales_invoice_header AS
SELECT
  TRIM(`No`)                                 AS invoice_no,
  TRIM(Sell_to_Customer_No)                AS customer_no,
  Posting_Date                             AS posting_date,
  Due_Date                                 AS due_date,
  NULLIF(TRIM(Payment_Terms_Code), '')     AS payment_terms_code,
  NULLIF(TRIM(Salesperson_Code), '')       AS salesperson_code,
  Shipment_Method_Code                     AS shipment_method_code,
  Order_No                                 AS sales_order_no,
  User_ID                                  AS posted_by_user,
  Amount                                   AS net_amount_eur,
  Amount_Including_VAT                     AS gross_amount_eur
FROM raw.sales_invoice_header;

-- ---------- 01_staging/stg_sales_invoice_line.sql ----------
-- Posted sales invoice lines (item lines only)
CREATE OR REPLACE VIEW staging.stg_sales_invoice_line AS
SELECT
  TRIM(Document_No)      AS invoice_no,
  Line_No                AS line_no,
  TRIM(`No`)               AS item_no,
  Quantity               AS quantity,
  Unit_Price             AS unit_price_eur,
  Line_Discount_Pct      AS discount_pct,
  Line_Discount_Amount   AS discount_amount_eur,
  Amount                 AS net_amount_eur,
  Amount_Including_VAT   AS gross_amount_eur,
  Unit_Cost_LCY          AS unit_cost_eur
FROM raw.sales_invoice_line
WHERE Type = 'Item';

-- ---------- 01_staging/stg_salesperson.sql ----------
CREATE OR REPLACE VIEW staging.stg_salesperson AS
SELECT
  TRIM(Code)      AS salesperson_code,
  TRIM(Name)      AS salesperson_name,
  TRIM(Region)    AS sales_region,
  TRIM(Territory) AS territory,
  LOWER(E_Mail)   AS email,
  Start_Date      AS start_date
FROM raw.salesperson;

-- ---------- 01_staging/stg_vendor.sql ----------
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

-- ---------- 02_mart/00_report_parameters.sql ----------
-- Single-row table with the reporting cut-off ("as of" date) used by all marts and checks
CREATE OR REPLACE TABLE mart.report_parameters AS
SELECT
  MAX(posting_date)                           AS report_date,
  DATE '2023-01-01'                           AS data_start_date,
  'Hanse Spirits Trading GmbH (fictional)'    AS company_name,
  25.0                                        AS max_discount_pct_policy,
  50000                                       AS po_cfo_approval_threshold_eur,
  'RBRANDT'                                   AS cfo_user_id
FROM staging.stg_sales_invoice_header
WHERE posting_date <= CURRENT_DATE();

-- ---------- 02_mart/01_dim_date.sql ----------
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

-- ---------- 02_mart/02_dim_salesperson.sql ----------
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

-- ---------- 02_mart/03_dim_item_category.sql ----------
-- Item categories. Shared by dim_item and the Excel sales budget (budget is planned per category).
CREATE OR REPLACE TABLE mart.dim_item_category AS
SELECT * FROM UNNEST([
  STRUCT('WHISKY' AS item_category_code, 'Whisky' AS item_category_name, 1 AS sort_order),
  STRUCT('GIN', 'Gin', 2),
  STRUCT('RUM', 'Rum', 3),
  STRUCT('VODKA', 'Vodka', 4),
  STRUCT('LIQUEUR', 'Liqueur', 5),
  STRUCT('BRANDY', 'Brandy & Cognac', 6),
  STRUCT('UNASSIGNED', '(Unassigned)', 99)
]);

-- ---------- 02_mart/04_dim_vendor.sql ----------
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

-- ---------- 02_mart/05_dim_item.sql ----------
-- Items with vendor attributes, lifecycle status and ABC class (last 12 months net revenue)
CREATE OR REPLACE TABLE mart.dim_item AS
WITH l12m AS (
  SELECT l.item_no, SUM(l.net_amount_eur) AS revenue_l12m
  FROM staging.stg_sales_invoice_line l
  JOIN staging.stg_sales_invoice_header h USING (invoice_no)
  CROSS JOIN mart.report_parameters p
  WHERE h.posting_date > DATE_SUB(p.report_date, INTERVAL 12 MONTH)
  GROUP BY l.item_no
),
abc AS (
  SELECT
    item_no,
    revenue_l12m,
    SUM(revenue_l12m) OVER (ORDER BY revenue_l12m DESC, item_no
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      / SUM(revenue_l12m) OVER ()                                      AS cumulative_share
  FROM l12m
)
SELECT
  i.item_no,
  i.item_description,
  COALESCE(i.item_category_code, 'UNASSIGNED')   AS item_category_code,
  i.brand,
  i.vendor_no,
  v.vendor_name,
  v.country_code                                 AS vendor_country_code,
  v.currency_code                                AS purchase_currency,
  i.country_of_origin,
  i.bottle_size_l,
  i.alcohol_pct,
  i.pure_alcohol_l_per_bottle,
  CASE
    WHEN i.alcohol_pct >= 50 THEN 'High proof (50 %+)'
    WHEN i.alcohol_pct >= 37.5 THEN 'Standard (37.5–49 %)'
    ELSE 'Liqueur strength (< 37.5 %)'
  END                                            AS strength_band,
  i.list_price_eur,
  CASE
    WHEN i.list_price_eur < 15 THEN '1 Value (< 15 €)'
    WHEN i.list_price_eur < 30 THEN '2 Standard (15–30 €)'
    WHEN i.list_price_eur < 60 THEN '3 Premium (30–60 €)'
    ELSE '4 Super premium (60 € +)'
  END                                            AS price_segment,
  i.unit_cost_eur,
  i.is_blocked,
  i.blocked_date,
  i.created_date,
  CASE
    WHEN i.is_blocked THEN 'Discontinued'
    WHEN i.created_date > DATE_SUB(p.report_date, INTERVAL 12 MONTH) THEN 'New (< 12 months)'
    ELSE 'Active'
  END                                            AS item_status,
  COALESCE(a.revenue_l12m, 0)                    AS revenue_l12m_eur,
  CASE
    WHEN a.revenue_l12m IS NULL OR a.revenue_l12m <= 0 THEN 'No sales L12M'
    WHEN a.cumulative_share <= 0.80 THEN 'A'
    WHEN a.cumulative_share <= 0.95 THEN 'B'
    ELSE 'C'
  END                                            AS abc_class
FROM staging.stg_item i
LEFT JOIN staging.stg_vendor v USING (vendor_no)
LEFT JOIN abc a USING (item_no)
CROSS JOIN mart.report_parameters p

UNION ALL
-- "unknown" member for invoice lines whose item number is missing in the item master
SELECT
  'UNKNOWN', '(Unknown item)', 'UNASSIGNED', '(Unknown)', CAST(NULL AS STRING), '(Unknown)',
  CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING),
  CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), '(Unknown)',
  CAST(NULL AS NUMERIC), '(Unknown)', CAST(NULL AS NUMERIC), FALSE, CAST(NULL AS DATE), CAST(NULL AS DATE),
  '(Unknown)', CAST(0 AS NUMERIC), 'No sales L12M';

-- ---------- 02_mart/06_dim_customer.sql ----------
-- Customers with channel, region, lifecycle status and ABC class
CREATE OR REPLACE TABLE mart.dim_customer AS
WITH inv AS (
  SELECT
    customer_no,
    MIN(posting_date)  AS first_invoice_date,
    MAX(posting_date)  AS last_invoice_date,
    COUNT(*)           AS invoice_count
  FROM staging.stg_sales_invoice_header
  GROUP BY customer_no
),
l12m AS (
  SELECT h.customer_no, SUM(h.net_amount_eur) AS revenue_l12m
  FROM staging.stg_sales_invoice_header h
  CROSS JOIN mart.report_parameters p
  WHERE h.posting_date > DATE_SUB(p.report_date, INTERVAL 12 MONTH)
  GROUP BY h.customer_no
),
abc AS (
  SELECT
    customer_no,
    revenue_l12m,
    SUM(revenue_l12m) OVER (ORDER BY revenue_l12m DESC, customer_no
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      / SUM(revenue_l12m) OVER () AS cumulative_share
  FROM l12m
)
SELECT
  c.customer_no,
  c.customer_name,
  c.channel_code,
  CASE c.channel_code
    WHEN 'HORECA'    THEN 'Bars & Restaurants'
    WHEN 'RETAIL'    THEN 'Retail'
    WHEN 'WHOLESALE' THEN 'Wholesale'
    WHEN 'ONLINE'    THEN 'E-Commerce'
    ELSE 'Unknown'
  END                                                 AS channel_name,
  c.city,
  c.post_code,
  c.federal_state,
  CASE
    WHEN c.federal_state IN ('Bremen', 'Hamburg', 'Niedersachsen', 'Schleswig-Holstein',
                             'Mecklenburg-Vorpommern') THEN 'Nord'
    WHEN c.federal_state IN ('Nordrhein-Westfalen', 'Hessen', 'Rheinland-Pfalz', 'Saarland') THEN 'West'
    WHEN c.federal_state IN ('Bayern', 'Baden-Württemberg') THEN 'Süd'
    WHEN c.federal_state IN ('Berlin', 'Brandenburg', 'Sachsen', 'Sachsen-Anhalt', 'Thüringen') THEN 'Ost'
    ELSE 'Unknown'
  END                                                 AS customer_region,
  c.country_code,
  c.latitude,
  c.longitude,
  COALESCE(c.salesperson_code, 'UNASSIGNED')          AS salesperson_code,
  c.salesperson_code = 'IK'                           AS is_key_account,
  c.payment_terms_code,
  c.credit_limit_eur,
  c.is_blocked,
  c.blocked_date,
  c.created_date,
  i.first_invoice_date,
  i.last_invoice_date,
  COALESCE(i.invoice_count, 0)                        AS invoice_count,
  DATE_DIFF(p.report_date, i.last_invoice_date, DAY)  AS days_since_last_invoice,
  CASE
    WHEN c.is_blocked THEN 'Blocked'
    WHEN i.last_invoice_date IS NULL THEN 'No sales yet'
    WHEN DATE_DIFF(p.report_date, i.last_invoice_date, DAY) > 180 THEN 'Lost (> 180 days)'
    WHEN DATE_DIFF(p.report_date, i.last_invoice_date, DAY) > 90 THEN 'At risk (91–180 days)'
    WHEN i.first_invoice_date > DATE_SUB(p.report_date, INTERVAL 12 MONTH) THEN 'New (< 12 months)'
    ELSE 'Active'
  END                                                 AS customer_status,
  COALESCE(a.revenue_l12m, 0)                         AS revenue_l12m_eur,
  CASE
    WHEN a.revenue_l12m IS NULL OR a.revenue_l12m <= 0 THEN 'No sales L12M'
    WHEN a.cumulative_share <= 0.80 THEN 'A'
    WHEN a.cumulative_share <= 0.95 THEN 'B'
    ELSE 'C'
  END                                                 AS abc_class
FROM staging.stg_customer c
LEFT JOIN inv i USING (customer_no)
LEFT JOIN abc a USING (customer_no)
CROSS JOIN mart.report_parameters p;

-- ---------- 02_mart/07_fx_rate_daily.sql ----------
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

-- ---------- 02_mart/08_fact_sales.sql ----------
-- Sales fact at invoice-line grain: revenue, discounts, cost, margin, volume and excise duty
CREATE OR REPLACE TABLE mart.fact_sales AS
SELECT
  l.invoice_no,
  l.line_no,
  h.posting_date,
  h.customer_no,
  COALESCE(h.salesperson_code, 'UNASSIGNED')                       AS salesperson_code,
  IF(i.item_no IS NULL, 'UNKNOWN', l.item_no)                      AS item_no,
  l.item_no                                                        AS source_item_no,
  l.quantity                                                       AS quantity_bottles,
  l.unit_price_eur,
  l.discount_pct,
  ROUND(l.quantity * l.unit_price_eur, 2)                          AS gross_sales_eur,
  l.discount_amount_eur,
  l.net_amount_eur                                                 AS net_sales_eur,
  l.unit_cost_eur,
  ROUND(l.quantity * l.unit_cost_eur, 2)                           AS cost_of_sales_eur,
  l.net_amount_eur - ROUND(l.quantity * l.unit_cost_eur, 2)        AS gross_margin_eur,
  l.quantity * i.bottle_size_l                                     AS volume_l,
  l.quantity * i.pure_alcohol_l_per_bottle                         AS pure_alcohol_l,
  -- excise duty contained in the (duty-paid) cost of goods
  ROUND(l.quantity * i.pure_alcohol_l_per_bottle * e.rate_eur_per_l_pure_alcohol, 2) AS excise_duty_eur
FROM staging.stg_sales_invoice_line l
JOIN staging.stg_sales_invoice_header h USING (invoice_no)
LEFT JOIN staging.stg_item i USING (item_no)
LEFT JOIN staging.stg_excise_rate e
  ON h.posting_date BETWEEN e.valid_from AND e.valid_to AND e.product_group = 'SPIRITS';

-- ---------- 02_mart/09_fact_purchase.sql ----------
-- Purchase fact at PO-line grain: spend in EUR (FX at order date) and delivery performance (OTIF)
CREATE OR REPLACE TABLE mart.fact_purchase AS
WITH receipts AS (
  SELECT
    order_no,
    item_no,
    MIN(posting_date)  AS first_receipt_date,
    SUM(quantity)      AS quantity_received_ledger
  FROM staging.stg_item_ledger_entry
  WHERE entry_type = 'Purchase'
  GROUP BY order_no, item_no
)
SELECT
  pl.po_no,
  pl.line_no,
  ph.order_date,
  ph.vendor_no,
  pl.item_no,
  ph.currency_code,
  ph.shipment_method_code,
  ph.created_by,
  ph.approved_by,
  pl.quantity                                                         AS quantity_ordered,
  pl.quantity_received,
  pl.direct_unit_cost_fc,
  pl.line_amount_fc,
  fx.rate_per_eur                                                     AS fx_rate_at_order,
  ROUND(pl.line_amount_fc / fx.rate_per_eur, 2)                       AS order_amount_eur,
  ROUND(pl.quantity_received * pl.direct_unit_cost_fc / fx.rate_per_eur, 2) AS received_amount_eur,
  pl.expected_receipt_date,
  r.first_receipt_date                                                AS actual_receipt_date,
  DATE_DIFF(r.first_receipt_date, pl.expected_receipt_date, DAY)      AS delivery_delay_days,
  DATE_DIFF(r.first_receipt_date, ph.order_date, DAY)                 AS actual_lead_time_days,
  -- on time = received no later than 2 days after the confirmed date
  CASE WHEN r.first_receipt_date IS NULL THEN NULL
       ELSE r.first_receipt_date <= DATE_ADD(pl.expected_receipt_date, INTERVAL 2 DAY) END AS is_on_time,
  CASE WHEN r.first_receipt_date IS NULL THEN NULL
       ELSE pl.quantity_received >= pl.quantity END                   AS is_in_full,
  CASE
    WHEN pl.quantity_received = 0 THEN 'Open'
    WHEN pl.quantity_received < pl.quantity THEN 'Partially received'
    ELSE 'Received'
  END                                                                 AS line_status
FROM staging.stg_purchase_line pl
JOIN staging.stg_purchase_header ph USING (po_no)
LEFT JOIN receipts r ON r.order_no = pl.po_no AND r.item_no = pl.item_no
LEFT JOIN mart.fx_rate_daily fx ON fx.rate_date = ph.order_date AND fx.currency_code = ph.currency_code;

-- ---------- 02_mart/10_fact_inventory_monthly.sql ----------
-- Month-end stock per item: quantity, value, movements, days of cover and stock health
CREATE OR REPLACE TABLE mart.fact_inventory_monthly AS
WITH months AS (
  SELECT DISTINCT d.month_end_date
  FROM mart.dim_date d
  CROSS JOIN mart.report_parameters p
  WHERE d.month_end_date BETWEEN DATE '2022-12-31' AND LAST_DAY(p.report_date, MONTH)
),
grid AS (
  SELECT i.item_no, m.month_end_date
  FROM staging.stg_item i
  CROSS JOIN months m
),
movements AS (
  SELECT
    item_no,
    GREATEST(LAST_DAY(posting_date, MONTH), DATE '2022-12-31')         AS month_end_date,
    SUM(quantity)                                                       AS net_qty,
    SUM(IF(entry_type = 'Purchase', quantity, 0))                       AS qty_received,
    SUM(IF(entry_type = 'Sale', -quantity, 0))                          AS qty_sold,
    SUM(IF(entry_type IN ('Positive Adjmt.', 'Negative Adjmt.')
           AND COALESCE(reason_code, '') <> 'OPENING', quantity, 0))   AS qty_adjusted
  FROM staging.stg_item_ledger_entry
  GROUP BY 1, 2
),
monthly_cost AS (
  SELECT item_no, LAST_DAY(posting_date, MONTH) AS month_end_date,
         SAFE_DIVIDE(SUM(cost_of_sales_eur), SUM(quantity_bottles)) AS avg_unit_cost
  FROM mart.fact_sales
  GROUP BY 1, 2
),
running AS (
  SELECT
    g.item_no,
    g.month_end_date,
    COALESCE(mv.qty_received, 0)  AS qty_received,
    COALESCE(mv.qty_sold, 0)      AS qty_sold,
    COALESCE(mv.qty_adjusted, 0)  AS qty_adjusted,
    SUM(COALESCE(mv.net_qty, 0)) OVER w_cum                                       AS closing_qty,
    COALESCE(LAST_VALUE(mc.avg_unit_cost IGNORE NULLS) OVER w_cum, i.unit_cost_eur) AS unit_cost_eur,
    AVG(COALESCE(mv.qty_sold, 0)) OVER (PARTITION BY g.item_no ORDER BY g.month_end_date
                                        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg_monthly_sold_3m,
    MAX(IF(COALESCE(mv.qty_sold, 0) > 0, g.month_end_date, NULL)) OVER w_cum      AS last_sale_month,
    i.created_date
  FROM grid g
  LEFT JOIN movements mv USING (item_no, month_end_date)
  LEFT JOIN monthly_cost mc USING (item_no, month_end_date)
  LEFT JOIN staging.stg_item i USING (item_no)
  WINDOW w_cum AS (PARTITION BY g.item_no ORDER BY g.month_end_date
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  item_no,
  month_end_date,
  qty_received,
  qty_sold,
  qty_adjusted,
  closing_qty,
  ROUND(unit_cost_eur, 4)                                        AS unit_cost_eur,
  ROUND(closing_qty * unit_cost_eur, 2)                          AS closing_value_eur,
  ROUND(avg_monthly_sold_3m, 2)                                  AS avg_monthly_sold_3m,
  ROUND(SAFE_DIVIDE(closing_qty, avg_monthly_sold_3m / 30.4), 1) AS days_of_cover,
  DATE_DIFF(month_end_date, last_sale_month, MONTH)              AS months_since_last_sale,
  CASE
    WHEN closing_qty < 0 THEN 'Negative stock'
    WHEN closing_qty = 0 THEN 'Out of stock'
    WHEN last_sale_month IS NULL OR DATE_DIFF(month_end_date, last_sale_month, MONTH) >= 6 THEN 'Dead stock (no sale 6M+)'
    WHEN SAFE_DIVIDE(closing_qty, avg_monthly_sold_3m / 30.4) > 180 THEN 'Slow moving (> 180 days cover)'
    WHEN SAFE_DIVIDE(closing_qty, avg_monthly_sold_3m / 30.4) > 90 THEN 'Excess (90–180 days cover)'
    ELSE 'Healthy'
  END                                                            AS stock_status
FROM running
WHERE month_end_date >= DATE '2023-01-31'
  AND (closing_qty <> 0 OR qty_sold <> 0 OR qty_received <> 0 OR created_date <= month_end_date);

-- ---------- 02_mart/11_fact_receivables.sql ----------
-- Receivables per invoice: payment behaviour, overdue days and ageing buckets as of the report date
CREATE OR REPLACE TABLE mart.fact_receivables AS
SELECT
  e.entry_no,
  e.invoice_no,
  e.customer_no,
  COALESCE(e.salesperson_code, 'UNASSIGNED')                         AS salesperson_code,
  e.posting_date,
  e.due_date,
  e.closed_at_date                                                   AS paid_date,
  e.amount_eur                                                       AS invoice_amount_eur,
  e.remaining_amount_eur                                             AS open_amount_eur,
  e.is_open,
  DATE_DIFF(e.closed_at_date, e.posting_date, DAY)                   AS days_to_pay,
  DATE_DIFF(e.closed_at_date, e.due_date, DAY)                       AS days_paid_late,
  IF(e.is_open, GREATEST(DATE_DIFF(p.report_date, e.due_date, DAY), 0), 0) AS days_overdue,
  CASE
    WHEN NOT e.is_open THEN 'Paid'
    WHEN p.report_date <= e.due_date THEN '0 Not yet due'
    WHEN DATE_DIFF(p.report_date, e.due_date, DAY) <= 30 THEN '1 Overdue 1–30'
    WHEN DATE_DIFF(p.report_date, e.due_date, DAY) <= 60 THEN '2 Overdue 31–60'
    WHEN DATE_DIFF(p.report_date, e.due_date, DAY) <= 90 THEN '3 Overdue 61–90'
    ELSE '4 Overdue > 90'
  END                                                                AS ageing_bucket
FROM staging.stg_cust_ledger_entry e
CROSS JOIN mart.report_parameters p;

-- ---------- 03_dq/01_check_catalog.sql ----------
-- Catalogue of automated data-quality and internal-control checks (ICS control matrix)
CREATE OR REPLACE TABLE dq.check_catalog AS
SELECT * FROM UNNEST([
  STRUCT(
    'C01' AS check_id, 'Sales below cost price' AS check_name, 'Pricing & margin' AS control_area,
    'High' AS risk_level,
    'Prevent loss-making sales and unauthorised price overrides' AS control_objective,
    'Invoice line net price per bottle is lower than the unit cost at time of sale' AS rule_description,
    'Head of Sales' AS control_owner, 'Daily' AS frequency),
  STRUCT('C02', 'Discount above policy limit', 'Pricing & margin', 'High',
    'Enforce the discount policy (max. 25 % per line without approval)',
    'Line discount % is greater than the policy limit in mart.report_parameters',
    'Head of Sales', 'Daily'),
  STRUCT('C03', 'Possible duplicate invoice', 'Revenue & billing', 'High',
    'Avoid double billing of customers',
    'Two or more invoices with the same customer, posting date and net amount',
    'Accounting', 'Daily'),
  STRUCT('C04', 'Sale to blocked customer', 'Credit management', 'High',
    'No deliveries to customers blocked by credit management',
    "Invoice posted on or after the customer's block date",
    'Credit Management', 'Daily'),
  STRUCT('C05', 'Posting on weekend / public holiday', 'Revenue & billing', 'Medium',
    'Detect postings outside regular business days (cut-off and manipulation risk)',
    'Invoice posting date is a Saturday, Sunday or Bremen public holiday',
    'Accounting', 'Weekly'),
  STRUCT('C06', 'Invoice line with unknown item', 'Data integrity', 'Medium',
    'Every sales line must reference a valid item master record',
    'Item number on invoice line does not exist in the item master',
    'Master Data Management', 'Daily'),
  STRUCT('C07', 'Credit limit exceeded', 'Credit management', 'High',
    'Limit default risk per customer',
    "Open receivables (incl. VAT) at report date exceed the customer's credit limit",
    'Credit Management', 'Daily'),
  STRUCT('C08', 'Receivable overdue > 90 days', 'Credit management', 'Medium',
    'Timely dunning and bad-debt provisioning',
    'Open invoice is more than 90 days past due date at report date',
    'Credit Management', 'Weekly'),
  STRUCT('C09', 'Purchase order self-approved', 'Purchasing (segregation of duties)', 'High',
    'Four-eyes principle: creator and approver of a PO must differ',
    'PO Created_By equals Approved_By',
    'Head of Purchasing', 'Daily'),
  STRUCT('C10', 'Purchase order without approval', 'Purchasing (segregation of duties)', 'High',
    'Every PO must be approved before it is sent to the vendor',
    'PO has no approver',
    'Head of Purchasing', 'Daily'),
  STRUCT('C11', 'PO above threshold not approved by CFO', 'Purchasing (segregation of duties)', 'High',
    'POs above the approval threshold require CFO sign-off',
    'PO value in EUR >= threshold and approver is not the CFO',
    'CFO', 'Weekly'),
  STRUCT('C12', 'Large stock adjustment without reason code', 'Inventory', 'Medium',
    'Explainable inventory write-offs, prevention of shrinkage/theft',
    'Inventory adjustment of 24+ bottles without reason code',
    'Warehouse Manager', 'Weekly'),
  STRUCT('C13', 'Negative stock at month end', 'Inventory', 'Low',
    'Stock records must reflect physical inventory',
    'Closing quantity of an item at month end is below zero',
    'Warehouse Manager', 'Monthly'),
  STRUCT('C14', 'Incomplete master data', 'Master data', 'Medium',
    'Complete master data for correct reporting and posting',
    'Customer without salesperson or post code, item without category, vendor without payment terms',
    'Master Data Management', 'Weekly'),
  STRUCT('C15', 'Possible duplicate customer', 'Master data', 'Medium',
    'One customer = one master record (credit limits, reporting, GDPR)',
    'Two customers with the same normalised name and post code',
    'Master Data Management', 'Weekly')
]);

-- ---------- 03_dq/02_exceptions.sql ----------
-- All control exceptions in one table (one row = one finding) for the Power BI controls page
CREATE OR REPLACE TABLE dq.exceptions AS
WITH p AS (SELECT * FROM mart.report_parameters),

c01 AS (
  SELECT 'C01' AS check_id, 'Invoice line' AS entity_type,
         CONCAT(invoice_no, '/', CAST(line_no AS STRING)) AS entity_id, invoice_no AS document_no,
         posting_date AS event_date, customer_no, CAST(NULL AS STRING) AS vendor_no, item_no, salesperson_code,
         CAST(cost_of_sales_eur - net_sales_eur AS FLOAT64) AS impact_eur,
         FORMAT('Net price %.2f EUR below unit cost %.2f EUR',
                CAST(net_sales_eur / quantity_bottles AS FLOAT64), CAST(unit_cost_eur AS FLOAT64)) AS detail
  FROM mart.fact_sales
  WHERE quantity_bottles > 0 AND net_sales_eur < cost_of_sales_eur
),
c02 AS (
  SELECT 'C02', 'Invoice line', CONCAT(f.invoice_no, '/', CAST(f.line_no AS STRING)), f.invoice_no,
         f.posting_date, f.customer_no, CAST(NULL AS STRING), f.item_no, f.salesperson_code,
         CAST(f.discount_amount_eur AS FLOAT64),
         FORMAT('Discount %.0f %% (policy max. %.0f %%)', CAST(f.discount_pct AS FLOAT64), p.max_discount_pct_policy)
  FROM mart.fact_sales f CROSS JOIN p
  WHERE f.discount_pct > p.max_discount_pct_policy
),
inv AS (
  SELECT
    invoice_no, customer_no, posting_date, net_amount_eur, salesperson_code,
    ROW_NUMBER()  OVER (PARTITION BY customer_no, posting_date, net_amount_eur ORDER BY invoice_no) AS rn,
    FIRST_VALUE(invoice_no) OVER (PARTITION BY customer_no, posting_date, net_amount_eur ORDER BY invoice_no) AS first_invoice_no
  FROM staging.stg_sales_invoice_header
),
c03 AS (
  SELECT 'C03', 'Invoice', invoice_no, invoice_no, posting_date, customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(salesperson_code, 'UNASSIGNED'), CAST(net_amount_eur AS FLOAT64),
         CONCAT('Same customer, date and amount as ', first_invoice_no)
  FROM inv WHERE rn > 1
),
c04 AS (
  SELECT 'C04', 'Invoice', h.invoice_no, h.invoice_no, h.posting_date, h.customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(h.salesperson_code, 'UNASSIGNED'), CAST(h.net_amount_eur AS FLOAT64),
         CONCAT('Customer blocked since ', CAST(c.blocked_date AS STRING))
  FROM staging.stg_sales_invoice_header h
  JOIN staging.stg_customer c USING (customer_no)
  WHERE c.is_blocked AND h.posting_date >= c.blocked_date
),
c05 AS (
  SELECT 'C05', 'Invoice', h.invoice_no, h.invoice_no, h.posting_date, h.customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(h.salesperson_code, 'UNASSIGNED'), CAST(h.net_amount_eur AS FLOAT64),
         CONCAT('Posted on ', d.weekday_short, COALESCE(CONCAT(' (', d.holiday_name, ')'), ''),
                ' by user ', h.posted_by_user)
  FROM staging.stg_sales_invoice_header h
  JOIN mart.dim_date d ON d.date = h.posting_date
  WHERE NOT d.is_business_day
),
c06 AS (
  SELECT 'C06', 'Invoice line', CONCAT(invoice_no, '/', CAST(line_no AS STRING)), invoice_no, posting_date,
         customer_no, CAST(NULL AS STRING), source_item_no, salesperson_code, CAST(net_sales_eur AS FLOAT64),
         CONCAT('Item ', source_item_no, ' not found in item master')
  FROM mart.fact_sales
  WHERE item_no = 'UNKNOWN'
),
open_ar AS (
  SELECT customer_no, SUM(open_amount_eur) AS open_amount_eur
  FROM mart.fact_receivables WHERE is_open GROUP BY customer_no
),
c07 AS (
  SELECT 'C07', 'Customer', c.customer_no, CAST(NULL AS STRING), p.report_date, c.customer_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), c.salesperson_code,
         CAST(o.open_amount_eur - c.credit_limit_eur AS FLOAT64),
         FORMAT('Open %.0f EUR vs. limit %.0f EUR', CAST(o.open_amount_eur AS FLOAT64),
                CAST(c.credit_limit_eur AS FLOAT64))
  FROM mart.dim_customer c JOIN open_ar o USING (customer_no) CROSS JOIN p
  WHERE o.open_amount_eur > c.credit_limit_eur
),
c08 AS (
  SELECT 'C08', 'Invoice', invoice_no, invoice_no, due_date, customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), salesperson_code, CAST(open_amount_eur AS FLOAT64),
         CONCAT(CAST(days_overdue AS STRING), ' days overdue')
  FROM mart.fact_receivables
  WHERE is_open AND days_overdue > 90
),
po AS (
  SELECT po_no, ANY_VALUE(vendor_no) AS vendor_no, ANY_VALUE(order_date) AS order_date,
         ANY_VALUE(created_by) AS created_by, ANY_VALUE(approved_by) AS approved_by,
         SUM(order_amount_eur) AS po_amount_eur
  FROM mart.fact_purchase GROUP BY po_no
),
c09 AS (
  SELECT 'C09', 'Purchase order', po_no, po_no, order_date, CAST(NULL AS STRING), vendor_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(po_amount_eur AS FLOAT64),
         CONCAT('Created and approved by ', created_by)
  FROM po WHERE created_by = approved_by
),
c10 AS (
  SELECT 'C10', 'Purchase order', po_no, po_no, order_date, CAST(NULL AS STRING), vendor_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(po_amount_eur AS FLOAT64),
         CONCAT('No approver; created by ', created_by)
  FROM po WHERE approved_by IS NULL
),
c11 AS (
  SELECT 'C11', 'Purchase order', po.po_no, po.po_no, po.order_date, CAST(NULL AS STRING), po.vendor_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(po.po_amount_eur AS FLOAT64),
         FORMAT('%.0f EUR approved by %s (CFO required)', CAST(po.po_amount_eur AS FLOAT64), po.approved_by)
  FROM po CROSS JOIN p
  WHERE po.po_amount_eur >= p.po_cfo_approval_threshold_eur
    AND po.approved_by IS NOT NULL AND po.approved_by <> p.cfo_user_id AND po.approved_by <> po.created_by
),
c12 AS (
  SELECT 'C12', 'Item ledger entry', CAST(e.entry_no AS STRING), e.document_no, e.posting_date,
         CAST(NULL AS STRING), CAST(NULL AS STRING), e.item_no, CAST(NULL AS STRING),
         CAST(ABS(e.quantity) * i.unit_cost_eur AS FLOAT64),
         FORMAT('%s of %.0f bottles without reason code', e.entry_type, CAST(e.quantity AS FLOAT64))
  FROM staging.stg_item_ledger_entry e
  LEFT JOIN staging.stg_item i USING (item_no)
  WHERE e.entry_type IN ('Positive Adjmt.', 'Negative Adjmt.')
    AND ABS(e.quantity) >= 24 AND e.reason_code IS NULL
),
c13 AS (
  SELECT 'C13', 'Item stock (month end)', CONCAT(item_no, '@', CAST(month_end_date AS STRING)), CAST(NULL AS STRING),
         month_end_date, CAST(NULL AS STRING), CAST(NULL AS STRING), item_no, CAST(NULL AS STRING),
         CAST(ABS(closing_value_eur) AS FLOAT64),
         FORMAT('Closing stock %.0f bottles', CAST(closing_qty AS FLOAT64))
  FROM mart.fact_inventory_monthly
  WHERE closing_qty < 0
),
c14 AS (
  SELECT 'C14', 'Customer', customer_no, CAST(NULL AS STRING), created_date, customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(salesperson_code, 'UNASSIGNED'), CAST(0 AS FLOAT64),
         ARRAY_TO_STRING([IF(salesperson_code IS NULL, 'salesperson missing', NULL),
                          IF(post_code IS NULL, 'post code missing', NULL)], ', ')
  FROM staging.stg_customer
  WHERE salesperson_code IS NULL OR post_code IS NULL
  UNION ALL
  SELECT 'C14', 'Item', item_no, CAST(NULL AS STRING), created_date, CAST(NULL AS STRING), vendor_no, item_no,
         CAST(NULL AS STRING), CAST(0 AS FLOAT64), 'item category missing'
  FROM staging.stg_item WHERE item_category_code IS NULL
  UNION ALL
  SELECT 'C14', 'Vendor', vendor_no, CAST(NULL AS STRING), CAST(NULL AS DATE), CAST(NULL AS STRING), vendor_no,
         CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(0 AS FLOAT64), 'payment terms missing'
  FROM staging.stg_vendor WHERE payment_terms_code IS NULL
),
dup_cust AS (
  SELECT
    customer_no, customer_name, post_code, created_date, salesperson_code,
    ROW_NUMBER()  OVER (PARTITION BY customer_name_key, post_code ORDER BY created_date, customer_no) AS rn,
    FIRST_VALUE(customer_no) OVER (PARTITION BY customer_name_key, post_code ORDER BY created_date, customer_no) AS original_no
  FROM staging.stg_customer
),
c15 AS (
  SELECT 'C15', 'Customer', customer_no, CAST(NULL AS STRING), created_date, customer_no, CAST(NULL AS STRING),
         CAST(NULL AS STRING), COALESCE(salesperson_code, 'UNASSIGNED'), CAST(0 AS FLOAT64),
         CONCAT('"', customer_name, '" looks like a duplicate of ', original_no)
  FROM dup_cust WHERE rn > 1
),
all_exceptions AS (
  SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03 UNION ALL
  SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06 UNION ALL
  SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09 UNION ALL
  SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12 UNION ALL
  SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
)
SELECT
  CONCAT(a.check_id, '|', a.entity_id) AS exception_id,
  a.*,
  ROUND(a.impact_eur, 2)               AS impact_eur_rounded,
  c.check_name,
  c.control_area,
  c.risk_level,
  c.control_owner,
  CURRENT_TIMESTAMP()                  AS checked_at
FROM all_exceptions a
JOIN dq.check_catalog c USING (check_id);

-- ---------- 03_dq/03_check_summary.sql ----------
-- One row per control: number of findings, financial impact and traffic-light status
CREATE OR REPLACE TABLE dq.check_summary AS
SELECT
  c.check_id,
  c.check_name,
  c.control_area,
  c.risk_level,
  c.control_owner,
  c.frequency,
  c.control_objective,
  c.rule_description,
  COUNT(e.exception_id)                       AS exception_count,
  COUNT(DISTINCT e.entity_id)                 AS affected_records,
  ROUND(COALESCE(SUM(e.impact_eur), 0), 2)    AS impact_eur,
  MIN(e.event_date)                           AS first_occurrence,
  MAX(e.event_date)                           AS last_occurrence,
  CASE
    WHEN COUNT(e.exception_id) = 0 THEN 'Passed'
    WHEN c.risk_level = 'High' THEN 'Failed – action required'
    ELSE 'Warning – review'
  END                                         AS control_status,
  CURRENT_TIMESTAMP()                         AS checked_at
FROM dq.check_catalog c
LEFT JOIN dq.exceptions e USING (check_id)
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;
