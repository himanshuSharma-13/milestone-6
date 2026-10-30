USE DATABASE PIP_QUALITY;
-- Zero rows is pass for the curated fact, nonzero expected for raw/quarantine checks.
SELECT 'raw_duplicate_cases' test, COUNT(*) result FROM (
 SELECT case_id FROM RAW.CASES GROUP BY 1 HAVING COUNT(*)>1)
UNION ALL SELECT 'missing_assessment_dates',COUNT(*) FROM RAW.CASES
 WHERE TRY_TO_DATE(assessment_date) IS NULL
UNION ALL SELECT 'invalid_date_order',COUNT(*) FROM RAW.CASES
 WHERE TRY_TO_DATE(decision_date)<TRY_TO_DATE(referral_date)
UNION ALL SELECT 'invalid_standardized_labels',COUNT(*) FROM STAGING.VALID_CASES
 WHERE status='CLOSED' AND (dl_decision NOT IN ('NO_AWARD','STANDARD','ENHANCED')
  OR mob_decision NOT IN ('NO_AWARD','STANDARD','ENHANCED'))
UNION ALL SELECT 'points_mismatch',COUNT(*) FROM STAGING.QUARANTINE
 WHERE quarantine_reason='POINTS_MISMATCH'
UNION ALL SELECT 'duplicate_fact_case',COUNT(*) FROM (
 SELECT case_id FROM CORE.FACT_CASE GROUP BY 1 HAVING COUNT(*)>1)
UNION ALL SELECT 'invalid_curated_dates',COUNT(*) FROM CORE.FACT_CASE
 WHERE assessment_date IS NULL OR (status='CLOSED' AND decision_date IS NULL)
 OR decision_date<referral_date;

SELECT quarantine_reason,COUNT(*) cases FROM STAGING.QUARANTINE GROUP BY 1 ORDER BY 1;
SELECT COUNT(*) curated_cases FROM CORE.FACT_CASE;
