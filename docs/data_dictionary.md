# Data dictionary

| Object | Grain and key | Main fields | Purpose |
|---|---|---|---|
| `RAW.CASES` | file row; `source_file,source_row` | IDs, dates, reported totals/bands, challenge flags | Untouched source, including duplicates and defects |
| `RAW.ACTIVITY_SCORES` | file row | case, component, activity, points | Twelve activity scores per case |
| `RAW.PEOPLE` | file row | claimant/assessor IDs, identifiers, team, region | Synthetic persons and assessor assignment |
| `STAGING.CASES_LATEST` | `case_id` | latest raw case fields | Stream/task merge and deduplication |
| `STAGING.ACTIVITY_LATEST` | `case_id,component,activity` | points | Latest activity row |
| `STAGING.PEOPLE_LATEST` | `case_id` | person and team fields | Latest person row |
| `STAGING.CASES_STANDARDIZED` | `case_id` | normalized bands, parsed dates, activity sums, `quarantine_reason`, `band_exception` | Quality rules |
| `STAGING.QUARANTINE` / `VALID_CASES` | `case_id` | standardized fields | Invalid / accepted split |
| `CORE.DIM_CLAIMANT` | `claimant_key` | claimant ID, masked name/NI/DOB/condition, age band | Claimant dimension |
| `CORE.DIM_ASSESSOR` | `assessor_key` | ID, name, team, effective dates | Type-2 assessor version |
| `CORE.DIM_REGION` | `region_key` | region | Region dimension |
| `CORE.DIM_ASSESSMENT_TYPE` | `type_key` | face-to-face/telephone/video/paper | Channel dimension |
| `CORE.DIM_DATE` | `date_key` | calendar date, year, month, month start | Role-playing referral/assessment/decision date |
| `CORE.FACT_CASE` | `case_id` | dimension keys, points, bands, challenge outcomes, turnaround | One valid case; row policy on team |
| `CORE.FACT_ACTIVITY_SCORE` | `score_key` | case ID, component, activity, points | One valid activity score |
| `MART.COMPONENT_OUTCOMES` | `case_id,component` | points, award band | Two closed decision rows per case |
| `MART.AWARD_RATES` | component, band, region, assessor, type | count, rate, mean points, median/P90 turnaround | Award KPI |
| `MART.OVERTURN_RATES` | challenge stage | challenged, overturned, rate | MR and appeal KPI |
| `MART.AT_RISK_CASES` | open case | days open and days to target | Caseload review |
| `MART.ASSESSOR_QUALITY` | assessor, team | mean QA score and exception rate | Human QA review |
| `MART.FUNNEL` | assessor | observed/expected rate and 95%/99.8% limits | Case-mix adjusted consistency |
| `MART.FAIRNESS_COMPARE` | group type and value | count and daily-living award rate | Assessor, region, type, age and condition comparisons |
| `MART.AUDIT_SAMPLE` | month, case | strata, risk, seed, rationale, run date | Immutable-by-procedure QA draw |
| `MART.OVERTURN_SCORECARD` | challenged case | score and observed outcome | Transparent QA triage |
