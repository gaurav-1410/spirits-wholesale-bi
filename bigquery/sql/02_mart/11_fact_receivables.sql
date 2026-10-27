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
