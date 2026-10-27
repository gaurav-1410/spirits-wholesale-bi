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
