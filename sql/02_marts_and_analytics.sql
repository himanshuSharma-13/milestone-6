USE DATABASE PIP_QUALITY;
USE WAREHOUSE PIP_WH;

-- Expand each closed case to its two components only inside this KPI query.
CREATE OR REPLACE VIEW MART.AWARD_RATES AS
WITH outcomes AS (
 SELECT assessor_id, region, assessment_type, turnaround_days,
  'DAILY_LIVING' component, dl_points points, dl_decision award_level
 FROM CORE.FACT_CASE WHERE status='CLOSED'
 UNION ALL
 SELECT assessor_id, region, assessment_type, turnaround_days,
  'MOBILITY', mob_points, mob_decision
 FROM CORE.FACT_CASE WHERE status='CLOSED'
)
SELECT component, award_level, region, assessor_id, assessment_type,
 COUNT(*) AS cases, COUNT(*) / NULLIF(SUM(COUNT(*)) OVER
   (PARTITION BY component,region,assessor_id,assessment_type),0) AS award_rate,
 AVG(points) AS avg_points, MEDIAN(turnaround_days) AS median_turnaround_days,
 PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY turnaround_days) AS p90_turnaround_days
FROM outcomes GROUP BY 1,2,3,4,5;

CREATE OR REPLACE VIEW MART.OVERTURN_RATES AS
SELECT 'MANDATORY_RECONSIDERATION' stage, SUM(mr_overturned) overturned,
 SUM(mr_flag) challenges, SUM(mr_overturned)/NULLIF(SUM(mr_flag),0) overturn_rate
FROM CORE.FACT_CASE
UNION ALL
SELECT 'APPEAL', SUM(appeal_overturned), SUM(appeal_flag),
 SUM(appeal_overturned)/NULLIF(SUM(appeal_flag),0) FROM CORE.FACT_CASE;

CREATE OR REPLACE VIEW MART.AT_RISK_CASES AS
SELECT case_id, assessor_id, team_id, region, assessment_type, referral_date,
 DATEDIFF('DAY',referral_date,CURRENT_DATE()) AS days_open,
 40 - DATEDIFF('DAY',referral_date,CURRENT_DATE()) AS days_to_target
FROM CORE.FACT_CASE WHERE status='OPEN'
 AND DATEDIFF('DAY',referral_date,CURRENT_DATE()) >= 35;

-- One summary covers audit quality by assessor and band exceptions by assessor/region.
CREATE OR REPLACE VIEW MART.ASSESSOR_REVIEW AS
SELECT assessor_id, region, COUNT(*) cases,
 AVG(audit_quality_score) avg_audit_quality_score,
 SUM(band_exception) exceptions, AVG(band_exception) exception_rate
FROM CORE.FACT_CASE GROUP BY 1,2;

-- Overall rates are adjusted for observed assessment type and condition mix.
-- These are descriptive control limits, not assessor performance judgments.
CREATE OR REPLACE VIEW MART.FUNNEL AS
WITH cells AS (
 SELECT assessment_type, condition_category, AVG(IFF(dl_decision='NO_AWARD',0,1)) p
 FROM CORE.FACT_CASE WHERE status='CLOSED'
 GROUP BY 1,2
), per_assessor AS (
 SELECT o.assessor_id, COUNT(*) n,
  SUM(IFF(o.dl_decision='NO_AWARD',0,1)) observed_awards,
  SUM(c.p) expected_awards, SUM(c.p*(1-c.p)) binomial_variance
 FROM CORE.FACT_CASE o JOIN cells c
  ON o.assessment_type=c.assessment_type AND o.condition_category=c.condition_category
 WHERE o.status='CLOSED' GROUP BY 1
)
SELECT assessor_id, n, observed_awards/n observed_rate, expected_awards/n expected_rate,
 GREATEST(0,(expected_awards-1.96*SQRT(binomial_variance))/n) lower_95,
 LEAST(1,(expected_awards+1.96*SQRT(binomial_variance))/n) upper_95,
 GREATEST(0,(expected_awards-3.09*SQRT(binomial_variance))/n) lower_998,
 LEAST(1,(expected_awards+3.09*SQRT(binomial_variance))/n) upper_998,
 IFF(observed_awards < expected_awards-3.09*SQRT(binomial_variance)
  OR observed_awards > expected_awards+3.09*SQRT(binomial_variance),1,0) outside_998
FROM per_assessor;

-- Transparent scorecard; evaluate only on cases with an observed challenge outcome.
-- It ranks files for human review; it never changes claimant awards.
CREATE OR REPLACE VIEW MART.OVERTURN_SCORECARD AS
SELECT case_id, assessor_id, region, assessment_type, condition_category,
 IFF(mr_overturned=1 OR appeal_overturned=1,1,0) AS overturned,
 LEAST(0.9,0.04
  + IFF(ABS(dl_points-8)<=2 OR ABS(dl_points-12)<=2
      OR ABS(mob_points-8)<=2 OR ABS(mob_points-12)<=2,0.12,0)
  + IFF(narrative_words<40,0.12,0)
  + IFF(turnaround_days>40,0.10,0)
  + IFF(band_exception=1,0.20,0)) AS risk_probability
FROM CORE.FACT_CASE WHERE mr_flag=1 OR appeal_flag=1;

CREATE TABLE IF NOT EXISTS MART.AUDIT_SAMPLE (
 sample_month DATE, case_id VARCHAR, region VARCHAR, assessment_type VARCHAR,
 outcome VARCHAR, risk_flag NUMBER, rationale VARCHAR, seed VARCHAR,
 run_date TIMESTAMP_NTZ, PRIMARY KEY (sample_month,case_id)
);
CREATE OR REPLACE PROCEDURE MART.DRAW_AUDIT_SAMPLE(P_MONTH DATE)
RETURNS VARCHAR LANGUAGE SQL EXECUTE AS OWNER AS
$$
BEGIN
 IF (EXISTS (SELECT 1 FROM MART.AUDIT_SAMPLE WHERE sample_month = :P_MONTH)) THEN
   RETURN 'Already drawn: immutable by procedure';
 END IF;
 INSERT INTO MART.AUDIT_SAMPLE
 WITH eligible AS (
  SELECT case_id, region, assessment_type, dl_decision outcome,
   IFF(ABS(dl_points-8)<=2 OR ABS(dl_points-12)<=2
    OR band_exception=1 OR narrative_words<40 OR turnaround_days>40,1,0) risk_flag
  FROM CORE.FACT_CASE
  WHERE DATE_TRUNC('MONTH',decision_date)::DATE = :P_MONTH
 ), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY region,assessment_type,outcome,risk_flag
      ORDER BY HASH(case_id,'PIP_AUDIT_V1',:P_MONTH)) AS rn,
   COUNT(*) OVER (PARTITION BY region,assessment_type,outcome,risk_flag) AS stratum_n
  FROM eligible
 )
 SELECT :P_MONTH, case_id, region, assessment_type, outcome, risk_flag,
  IFF(risk_flag=1,'20% high-risk stratum','10% base stratum'),
  'PIP_AUDIT_V1', CURRENT_TIMESTAMP()
 FROM ranked WHERE rn <= CEIL(stratum_n * IFF(risk_flag=1,0.20,0.10));
 RETURN 'Sample drawn';
END;
$$;
-- Once, after loading. Change to the intended month if demo data has no current-month decisions.
CALL MART.DRAW_AUDIT_SAMPLE(DATE_TRUNC('MONTH',CURRENT_DATE())::DATE);
