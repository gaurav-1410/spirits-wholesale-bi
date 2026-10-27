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
