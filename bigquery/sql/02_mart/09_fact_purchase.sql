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
