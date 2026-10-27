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
