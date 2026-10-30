-- Run after granting the three roles to the same user and mapping that user to TEAM_A.
USE DATABASE PIP_QUALITY;
USE WAREHOUSE PIP_WH;
USE SECONDARY ROLES NONE;
USE ROLE ASSESSMENT_ADMIN;
SELECT CURRENT_ROLE() role_name, COUNT(*) visible_cases,
  COUNT(DISTINCT team_id) visible_teams FROM CORE.FACT_CASE;
SELECT CURRENT_ROLE() role_name, claimant_name, ni_number, date_of_birth,
  health_condition FROM CORE.DIM_CLAIMANT LIMIT 1;
USE ROLE QA_REVIEWER;
SELECT CURRENT_ROLE() role_name, COUNT(*) visible_cases,
  COUNT(DISTINCT team_id) visible_teams FROM CORE.FACT_CASE;
SELECT CURRENT_ROLE() role_name, claimant_name, ni_number, date_of_birth,
  health_condition FROM CORE.DIM_CLAIMANT LIMIT 1;
USE ROLE ASSESSOR_TEAM_VIEWER;
SELECT CURRENT_ROLE() role_name, COUNT(*) visible_cases,
  COUNT(DISTINCT team_id) visible_teams FROM CORE.FACT_CASE;
-- Team viewer has no direct permission on CORE.DIM_CLAIMANT; this query should fail.
SELECT CURRENT_ROLE() role_name, claimant_name, ni_number, date_of_birth,
  health_condition FROM CORE.DIM_CLAIMANT LIMIT 1;
