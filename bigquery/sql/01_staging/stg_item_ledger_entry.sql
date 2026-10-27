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
