-- Run after 02 and 03; save the results with the submission.
-- These are one-off analysis queries, so they do not need permanent MART views.
USE ROLE ASSESSMENT_ADMIN;
USE DATABASE PIP_QUALITY;
USE WAREHOUSE PIP_WH;

-- Assessor-only audit quality KPI from the assessor/region review summary.
SELECT assessor_id, SUM(cases) cases,
 SUM(avg_audit_quality_score * cases) / NULLIF(SUM(cases),0) avg_audit_quality_score
FROM MART.ASSESSOR_REVIEW GROUP BY assessor_id ORDER BY assessor_id;

-- Fairness: compare daily-living award rates with sample sizes.
-- The one-page fairness note discusses case mix and why a raw gap is not proof of bias.
WITH base AS (
 SELECT f.assessor_id, f.region, f.assessment_type, f.condition_category,
  d.age_band, IFF(f.dl_decision='NO_AWARD',0,1) AS awarded
 FROM CORE.FACT_CASE f JOIN CORE.DIM_CLAIMANT d ON f.claimant_key=d.claimant_key
 WHERE f.status='CLOSED'
)
SELECT 'ASSESSOR' group_type, assessor_id group_value, COUNT(*) n, AVG(awarded) award_rate
 FROM base GROUP BY assessor_id
UNION ALL SELECT 'REGION', region, COUNT(*), AVG(awarded) FROM base GROUP BY region
UNION ALL SELECT 'ASSESSMENT_TYPE', assessment_type, COUNT(*), AVG(awarded)
 FROM base GROUP BY assessment_type
UNION ALL SELECT 'AGE_BAND', age_band, COUNT(*), AVG(awarded) FROM base GROUP BY age_band
UNION ALL SELECT 'CONDITION_CATEGORY', condition_category, COUNT(*), AVG(awarded)
 FROM base GROUP BY condition_category;

-- Evaluate the transparent scorecard on the same held-out fifth of cases.
WITH heldout AS (
 SELECT *, IFF(risk_probability>=0.25,1,0) AS prediction
 FROM MART.OVERTURN_SCORECARD WHERE MOD(ABS(HASH(case_id)),5)=0
)
SELECT COUNT(*) heldout_n,
 SUM(IFF(prediction=1 AND overturned=1,1,0)) / NULLIF(SUM(prediction),0) precision,
 SUM(IFF(prediction=1 AND overturned=1,1,0)) / NULLIF(SUM(overturned),0) recall,
 AVG(risk_probability) mean_predicted, AVG(overturned) observed_rate
FROM heldout;

-- Calibration: compare average predicted score with actual overturn frequency.
SELECT FLOOR(risk_probability*5)/5 AS probability_bucket, COUNT(*) n,
 AVG(risk_probability) mean_predicted, AVG(overturned) observed_rate
FROM MART.OVERTURN_SCORECARD WHERE MOD(ABS(HASH(case_id)),5)=0
GROUP BY 1 ORDER BY 1;
