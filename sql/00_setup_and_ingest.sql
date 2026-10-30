-- Run as ACCOUNTADMIN (or a role allowed to create DB, warehouse and monitor).
CREATE WAREHOUSE IF NOT EXISTS PIP_WH WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
CREATE OR REPLACE RESOURCE MONITOR PIP_MONITOR WITH CREDIT_QUOTA = 20
  FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE PIP_WH SET RESOURCE_MONITOR = PIP_MONITOR;
CREATE DATABASE IF NOT EXISTS PIP_QUALITY;
CREATE SCHEMA IF NOT EXISTS PIP_QUALITY.RAW;
CREATE SCHEMA IF NOT EXISTS PIP_QUALITY.STAGING;
CREATE SCHEMA IF NOT EXISTS PIP_QUALITY.CORE;
CREATE SCHEMA IF NOT EXISTS PIP_QUALITY.MART;
CREATE SCHEMA IF NOT EXISTS PIP_QUALITY.SECURITY;
USE DATABASE PIP_QUALITY;
USE WAREHOUSE PIP_WH;
CREATE FILE FORMAT IF NOT EXISTS RAW.CSV_FMT TYPE = CSV SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"' NULL_IF = ('');
CREATE STAGE IF NOT EXISTS RAW.INPUT_STAGE FILE_FORMAT = RAW.CSV_FMT;

-- COPY is simpler and cheaper than Snowpipe for a three-file, interview-size batch.
-- Upload first with SnowSQL: PUT file://<absolute-path>/data/*.csv @RAW.INPUT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
CREATE TABLE IF NOT EXISTS RAW.CASES (
  case_id VARCHAR, claimant_id VARCHAR, assessor_id VARCHAR, region VARCHAR,
  assessment_type VARCHAR, referral_date VARCHAR, assessment_date VARCHAR,
  decision_date VARCHAR, dl_points VARCHAR, mob_points VARCHAR,
  dl_decision VARCHAR, mob_decision VARCHAR, mr_flag VARCHAR,
  mr_overturned VARCHAR, appeal_flag VARCHAR, appeal_overturned VARCHAR,
  status VARCHAR, audit_quality_score VARCHAR, narrative_words VARCHAR,
  condition_category VARCHAR, source_type VARCHAR,
  source_file VARCHAR, source_row NUMBER, loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
CREATE TABLE IF NOT EXISTS RAW.ACTIVITY_SCORES (
  case_id VARCHAR, component VARCHAR, activity VARCHAR, points VARCHAR,
  source_file VARCHAR, source_row NUMBER
);
CREATE TABLE IF NOT EXISTS RAW.PEOPLE (
  case_id VARCHAR, claimant_id VARCHAR, claimant_name VARCHAR, ni_number VARCHAR,
  date_of_birth VARCHAR, health_condition VARCHAR, assessor_id VARCHAR,
  assessor_name VARCHAR, team_id VARCHAR, region VARCHAR, valid_from VARCHAR,
  source_file VARCHAR, source_row NUMBER
);

-- Streams must exist before COPY so the first batch is visible to the tasks.
CREATE STREAM IF NOT EXISTS RAW.CASES_STREAM ON TABLE RAW.CASES APPEND_ONLY = TRUE;
CREATE STREAM IF NOT EXISTS RAW.ACTIVITY_STREAM ON TABLE RAW.ACTIVITY_SCORES APPEND_ONLY = TRUE;
CREATE STREAM IF NOT EXISTS RAW.PEOPLE_STREAM ON TABLE RAW.PEOPLE APPEND_ONLY = TRUE;

COPY INTO RAW.CASES (case_id, claimant_id, assessor_id, region, assessment_type,
  referral_date, assessment_date, decision_date, dl_points, mob_points,
  dl_decision, mob_decision, mr_flag, mr_overturned, appeal_flag,
  appeal_overturned, status, audit_quality_score, narrative_words,
  condition_category, source_type, source_file, source_row)
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,
  METADATA$FILENAME,METADATA$FILE_ROW_NUMBER FROM @RAW.INPUT_STAGE/cases.csv)
FILE_FORMAT = (FORMAT_NAME = RAW.CSV_FMT) ON_ERROR = ABORT_STATEMENT;
COPY INTO RAW.ACTIVITY_SCORES (case_id,component,activity,points,source_file,source_row)
FROM (SELECT $1,$2,$3,$4,METADATA$FILENAME,METADATA$FILE_ROW_NUMBER
  FROM @RAW.INPUT_STAGE/activity_scores.csv)
FILE_FORMAT = (FORMAT_NAME = RAW.CSV_FMT) ON_ERROR = ABORT_STATEMENT;
COPY INTO RAW.PEOPLE (case_id,claimant_id,claimant_name,ni_number,date_of_birth,
  health_condition,assessor_id,assessor_name,team_id,region,valid_from,source_file,source_row)
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,METADATA$FILENAME,METADATA$FILE_ROW_NUMBER
  FROM @RAW.INPUT_STAGE/people.csv)
FILE_FORMAT = (FORMAT_NAME = RAW.CSV_FMT) ON_ERROR = ABORT_STATEMENT;
