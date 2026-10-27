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
