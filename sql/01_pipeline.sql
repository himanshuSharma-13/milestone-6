USE DATABASE PIP_QUALITY;
USE WAREHOUSE PIP_WH;

-- Each dynamic table keeps one latest row per business key. Snowflake refreshes
-- changed rows after new COPY loads; no stream, task, or hand-written MERGE is needed.
CREATE OR REPLACE DYNAMIC TABLE STAGING.CASES_LATEST
  TARGET_LAG = '1 hour' WAREHOUSE = PIP_WH REFRESH_MODE = INCREMENTAL AS
SELECT * FROM RAW.CASES
QUALIFY ROW_NUMBER() OVER (PARTITION BY case_id
  ORDER BY loaded_at DESC, source_row DESC) = 1;

CREATE OR REPLACE DYNAMIC TABLE STAGING.ACTIVITY_LATEST
  TARGET_LAG = '1 hour' WAREHOUSE = PIP_WH REFRESH_MODE = INCREMENTAL AS
SELECT * FROM RAW.ACTIVITY_SCORES
QUALIFY ROW_NUMBER() OVER (PARTITION BY case_id, component, activity
  ORDER BY loaded_at DESC, source_row DESC) = 1;

CREATE OR REPLACE DYNAMIC TABLE STAGING.PEOPLE_LATEST
  TARGET_LAG = '1 hour' WAREHOUSE = PIP_WH REFRESH_MODE = INCREMENTAL AS
SELECT * FROM RAW.PEOPLE
QUALIFY ROW_NUMBER() OVER (PARTITION BY case_id
  ORDER BY loaded_at DESC, source_row DESC) = 1;

CREATE OR REPLACE VIEW STAGING.ACTIVITY AS
SELECT case_id, component, activity, TRY_TO_NUMBER(points) AS points
FROM STAGING.ACTIVITY_LATEST;

CREATE OR REPLACE VIEW STAGING.PEOPLE AS
SELECT case_id, claimant_id, claimant_name, ni_number,
  TRY_TO_DATE(date_of_birth) AS date_of_birth, health_condition,
  assessor_id, assessor_name, team_id, region,
  TRY_TO_DATE(valid_from) AS valid_from
FROM STAGING.PEOPLE_LATEST;

CREATE OR REPLACE VIEW STAGING.CASES_STANDARDIZED AS
WITH normalized AS (
 SELECT c.case_id, c.claimant_id, c.assessor_id, c.region,
  LOWER(c.assessment_type) AS assessment_type,
  TRY_TO_DATE(c.referral_date) AS referral_date,
  TRY_TO_DATE(c.assessment_date) AS assessment_date,
  TRY_TO_DATE(c.decision_date) AS decision_date,
  TRY_TO_NUMBER(c.dl_points) AS dl_points,
  TRY_TO_NUMBER(c.mob_points) AS mob_points,
  CASE WHEN LOWER(c.dl_decision) IN ('enhanced','enh','enhanced rate') THEN 'ENHANCED'
       WHEN LOWER(c.dl_decision) IN ('standard','std','standard rate') THEN 'STANDARD'
       WHEN LOWER(c.dl_decision) IN ('no award','none') THEN 'NO_AWARD' END AS dl_decision,
  CASE WHEN LOWER(c.mob_decision) IN ('enhanced','enh','enhanced rate') THEN 'ENHANCED'
       WHEN LOWER(c.mob_decision) IN ('standard','std','standard rate') THEN 'STANDARD'
       WHEN LOWER(c.mob_decision) IN ('no award','none') THEN 'NO_AWARD' END AS mob_decision,
  TRY_TO_NUMBER(c.mr_flag) AS mr_flag, TRY_TO_NUMBER(c.mr_overturned) AS mr_overturned,
  TRY_TO_NUMBER(c.appeal_flag) AS appeal_flag,
  TRY_TO_NUMBER(c.appeal_overturned) AS appeal_overturned,
  c.status, TRY_TO_NUMBER(c.audit_quality_score) AS audit_quality_score,
  TRY_TO_NUMBER(c.narrative_words) AS narrative_words, c.condition_category,
  p.team_id, p.claimant_name, p.ni_number, p.date_of_birth, p.health_condition,
  p.assessor_name
 FROM STAGING.CASES_LATEST c LEFT JOIN STAGING.PEOPLE p ON c.case_id = p.case_id
), totals AS (
 SELECT case_id,
  SUM(IFF(component='DL',points,0)) AS dl_activity_points,
  SUM(IFF(component='MOB',points,0)) AS mob_activity_points,
  COUNT(*) AS activity_count
 FROM STAGING.ACTIVITY GROUP BY case_id
)
SELECT n.*, t.dl_activity_points, t.mob_activity_points, t.activity_count,
 CASE WHEN n.case_id IS NULL OR n.claimant_id IS NULL OR n.assessor_id IS NULL THEN 'MISSING_KEY'
      WHEN n.referral_date IS NULL OR n.assessment_date IS NULL
        OR (n.status='CLOSED' AND n.decision_date IS NULL) THEN 'MISSING_DATE'
      WHEN n.decision_date < n.referral_date THEN 'DATE_ORDER'
      WHEN n.status='CLOSED' AND (n.dl_decision IS NULL OR n.mob_decision IS NULL) THEN 'INVALID_LABEL'
      WHEN t.activity_count <> 12 OR t.activity_count IS NULL THEN 'MISSING_ACTIVITY'
      WHEN n.dl_points <> t.dl_activity_points OR n.mob_points <> t.mob_activity_points THEN 'POINTS_MISMATCH'
      ELSE NULL END AS quarantine_reason,
 IFF(n.status='CLOSED' AND (n.dl_decision <> CASE WHEN t.dl_activity_points >= 12 THEN 'ENHANCED'
                              WHEN t.dl_activity_points >= 8 THEN 'STANDARD' ELSE 'NO_AWARD' END
     OR n.mob_decision <> CASE WHEN t.mob_activity_points >= 12 THEN 'ENHANCED'
                                WHEN t.mob_activity_points >= 8 THEN 'STANDARD' ELSE 'NO_AWARD' END),1,0)
 AS band_exception
FROM normalized n LEFT JOIN totals t ON n.case_id = t.case_id;

CREATE OR REPLACE VIEW STAGING.QUARANTINE AS
SELECT * FROM STAGING.CASES_STANDARDIZED WHERE quarantine_reason IS NOT NULL;
CREATE OR REPLACE VIEW STAGING.VALID_CASES AS
SELECT * FROM STAGING.CASES_STANDARDIZED WHERE quarantine_reason IS NULL;

CREATE OR REPLACE VIEW CORE.DIM_REGION AS
SELECT HASH(region) AS region_key, region FROM (SELECT DISTINCT region FROM STAGING.VALID_CASES);
CREATE OR REPLACE VIEW CORE.DIM_ASSESSMENT_TYPE AS
SELECT HASH(assessment_type) AS type_key, assessment_type
FROM (SELECT DISTINCT assessment_type FROM STAGING.VALID_CASES);
CREATE OR REPLACE VIEW CORE.DIM_DATE AS
SELECT DISTINCT HASH(d) AS date_key, d AS calendar_date, YEAR(d) AS year,
  MONTH(d) AS month, DATE_TRUNC('MONTH',d)::DATE AS month_start
FROM (SELECT referral_date d FROM STAGING.VALID_CASES UNION
      SELECT assessment_date FROM STAGING.VALID_CASES UNION
      SELECT decision_date FROM STAGING.VALID_CASES WHERE decision_date IS NOT NULL);
CREATE OR REPLACE VIEW CORE.DIM_CLAIMANT AS
SELECT HASH(claimant_id) AS claimant_key, claimant_id, claimant_name, ni_number,
  date_of_birth, health_condition,
  CASE WHEN DATEDIFF('YEAR',date_of_birth,CURRENT_DATE()) < 40 THEN 'UNDER_40'
       WHEN DATEDIFF('YEAR',date_of_birth,CURRENT_DATE()) < 65 THEN '40_64' ELSE '65_PLUS' END age_band
FROM STAGING.VALID_CASES
QUALIFY ROW_NUMBER() OVER (PARTITION BY claimant_id ORDER BY referral_date DESC) = 1;

-- Type 2 assessor dimension: one version per observed team assignment. A001 moves
-- from TEAM_A to TEAM_B in the synthetic data. Fact joins the version at referral.
CREATE OR REPLACE VIEW CORE.DIM_ASSESSOR AS
WITH versions AS (
 SELECT assessor_id, assessor_name, team_id, MIN(referral_date) AS effective_from
 FROM STAGING.VALID_CASES GROUP BY 1,2,3
)
SELECT HASH(assessor_id,team_id) assessor_key, assessor_id, assessor_name, team_id,
 effective_from,
 LEAD(effective_from) OVER (PARTITION BY assessor_id ORDER BY effective_from) AS effective_to,
 IFF(LEAD(effective_from) OVER (PARTITION BY assessor_id ORDER BY effective_from) IS NULL,1,0) AS is_current
FROM versions;

-- One fact row per case; MART.AWARD_RATES expands closed cases to two components.
CREATE OR REPLACE VIEW CORE.FACT_CASE AS
SELECT c.case_id, HASH(c.claimant_id) AS claimant_key, a.assessor_key,
 HASH(c.region) AS region_key, HASH(c.assessment_type) AS type_key,
 HASH(c.referral_date) AS referral_date_key,
 HASH(c.assessment_date) AS assessment_date_key,
 HASH(c.decision_date) AS decision_date_key,
 c.claimant_id, c.assessor_id, c.team_id, c.region, c.assessment_type,
 c.referral_date, c.assessment_date, c.decision_date,
 c.dl_points, c.mob_points, c.dl_decision, c.mob_decision,
 c.mr_flag, c.mr_overturned, c.appeal_flag, c.appeal_overturned,
 c.status, c.audit_quality_score, c.narrative_words, c.condition_category,
 c.band_exception, DATEDIFF('DAY',c.referral_date,c.decision_date) AS turnaround_days
FROM STAGING.VALID_CASES c JOIN CORE.DIM_ASSESSOR a
 ON c.assessor_id=a.assessor_id AND c.referral_date >= a.effective_from
 AND (a.effective_to IS NULL OR c.referral_date < a.effective_to);

CREATE OR REPLACE VIEW CORE.FACT_ACTIVITY_SCORE AS
SELECT a.case_id, HASH(a.case_id,a.component,a.activity) AS score_key,
 a.component, a.activity, a.points
FROM STAGING.ACTIVITY a JOIN CORE.FACT_CASE c ON a.case_id=c.case_id;
