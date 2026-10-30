# PIP assessment quality analytics (synthetic demo)

A small, explainable Snowflake project for the candidate assignment. All names, National Insurance numbers and health categories are **fabricated**. Outputs support human quality review; they do not make decisions about claimants or assessors.

## Run order

1. `python3 scripts/generate_data.py` writes exactly three CSVs in `data/` (3,200 distinct cases). `python3 scripts/local_evidence.py` writes reproducible local smoke results to `evidence/`.
2. In a Snowflake trial account, run `sql/00_setup_and_ingest.sql` as a role allowed to create a warehouse, database, roles and resource monitor. Before its COPY statements, upload the files to `@PIP_QUALITY.RAW.INPUT_STAGE`. SnowSQL example: `PUT file:///absolute/path/to/data/*.csv @PIP_QUALITY.RAW.INPUT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;` Snowflake worksheets cannot execute `PUT`; use SnowSQL or upload the three files through Snowsight. If using the worksheet, run the DDL part of `00`, upload, then run the three COPY commands.
3. Run `sql/01_pipeline.sql`, wait for the three `STAGING.REFRESH_*` tasks to finish, then run `sql/02_marts_and_analytics.sql` and `sql/03_security.sql` in that order. Run `sql/04_quality_tests.sql` and save its Snowflake output. `sql/05_role_test.sql` needs a real user mapped to a team and all three roles granted to that user; save the real output separately.
4. Create a Streamlit in Snowflake app from `app/streamlit_app.py` with `requirements.txt` dependencies, using a role that can read CORE and MART.

The SQL files are intentionally numbered and short enough to explain. `COPY INTO` loads three fixed CSVs once; Snowpipe would add setup and running costs without helping this batch. Subsequent COPY loads are captured by three append-only streams. Three five-minute tasks merge them into latest-row staging tables. The remaining standardized, quarantined, CORE and MART views always reflect that staging state. To rerun from scratch, recreate the database; do not rerun the numbered scripts against a production database without reviewing role and policy changes.

## Architecture and grain

```mermaid
flowchart LR
  CSV[3 synthetic CSVs] --> STAGE[Internal stage]
  STAGE --> RAW[RAW tables via COPY]
  RAW --> STREAM[3 append-only streams]
  STREAM --> TASK[3 merge tasks]
  TASK --> STAGING[STAGING latest, standardized, quarantine]
  STAGING --> CORE[CORE star schema views]
  CORE --> MART[MART KPI, sample, funnel, scorecard]
  MART --> APP[Streamlit QA views]
```

```mermaid
erDiagram
  DIM_CLAIMANT ||--o{ FACT_CASE : claimant_key
  DIM_ASSESSOR ||--o{ FACT_CASE : assessor_key
  DIM_REGION ||--o{ FACT_CASE : region_key
  DIM_ASSESSMENT_TYPE ||--o{ FACT_CASE : type_key
  DIM_DATE ||--o{ FACT_CASE : referral_date_key
  FACT_CASE ||--o{ FACT_ACTIVITY_SCORE : case_id
```

`CORE.FACT_CASE` has one row per valid case. `CORE.FACT_ACTIVITY_SCORE` has one row per case and activity. `CORE.DIM_ASSESSOR` is a simple type-2 dimension: each observed team assignment has an effective start and end; a case joins the version valid on its referral date. The generator moves assessor A001 from TEAM_A to TEAM_B in 2026. This small demo assumes no assessor returns to a previous team; a production type-2 table would use assignment event IDs and merge new versions. See [data dictionary](docs/data_dictionary.md).

## Assumptions and choices

- Daily living has ten activities and mobility two, with points `0,2,4,8,12`. This is a simplified scoring model for demonstration. Component bands are no award `<8`, standard `8–11`, enhanced `12+`. Actual PIP policy and exceptional decisions require specialist review.
- The turnaround target is **40 calendar days** from referral; an open case is at risk at day 35. Open cases have no decision date or award label. Missing assessment dates, invalid chronology and points totals that differ from the activity sum are quarantined. A recorded award that differs from the implied band stays in CORE with an exception flag for QA review.
- `audit_quality_score` is a synthetic 1–5 reviewer score. An assessor average is descriptive only.
- Mandatory reconsideration and appeal overturn rates use challenged cases as denominators. The scorecard is evaluated only on cases with a recorded challenge. It does not estimate overturn probability for all decisions without selection bias.
- The assignment's current-month sample is keyed by decision month. The seed and rationale are stored. The procedure returns without changing an existing month; only admins should have table write access. In a production system also restrict ownership and log procedure calls.
- The month has many tiny region × type × outcome × risk strata. A minimum of one per occupied stratum raises the sample fraction; reviewer capacity is about 45 files for the October demo. The sample is useful for broad QA coverage, not a precise population prevalence estimate. For 42 of 55 eligible cases, a worst-case 95% margin with finite-population correction is roughly ±7.5%; this does not cover nonresponse or measurement error.

## Evidence and current status

The checked-in [local results](evidence/local_results.json) are calculated directly from the synthetic CSVs, not from Snowflake. They show 32 duplicate case IDs, 171 quarantined cases, 3,029 curated cases, zero curated duplicate IDs/date errors/invalid labels, and a 42-case October sample. [Sample rows](evidence/local_sample_example.csv) use Python SHA-256, while the Snowflake stored procedure uses `HASH`; case IDs can therefore differ. The [local funnel dataset](evidence/local_funnel_example.csv) provides chart-ready values for 40 assessors. `sql/04_quality_tests.sql` and `sql/05_role_test.sql` are the **actual Snowflake evidence scripts**; their output cannot be asserted until run in a Snowflake account. Do not present local expected role counts as observed access-control results.

The model's held-out local precision and recall are poor (see `evidence/local_results.json`). This is an honest result: the generator assigns challenge outcomes mostly at random, so a transparent heuristic has little signal. The model is a QA triage demonstration only. It excludes names, NI numbers, date of birth, health category, region, assessor ID and protected characteristics as predictors. Its inputs are closeness to threshold, short narrative, long turnaround, and point-band exception. The local Python split differs from Snowflake `HASH`, so re-check SQL metrics after deployment.

## Governance, retention and cost

`ASSESSMENT_ADMIN` can see identifiers; `QA_REVIEWER` sees masked identifiers but all case rows; `ASSESSOR_TEAM_VIEWER` sees only rows for teams assigned in `SECURITY.USER_TEAMS` and has no direct claimant dimension grant. Masking and row-access policies are on the exposed CORE views. RAW and STAGING are admin-only. Object tags mark direct identifiers and health data. Real grants must be assigned to actual users before the role test.

Audit query access using `SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY` (allow for view latency), join `QUERY_HISTORY` for user, role and time, and review `policies_referenced` and `objects_modified`. Retention: define an approved period, expire old RAW/CORE data and staged files, and set Time Travel to the minimum permitted by policy. A subject access request can locate `claimant_id` in RAW and curated data and export authorized records. A verified deletion request must remove the claimant's rows from all three RAW sources, latest staging tables and the persisted audit sample; views then update. Purge stage files or replace them with redacted batches, and account for Time Travel/Fail-safe expiry and backups. Log approval and completion. Legal retention exceptions need a documented hold.

Use X-Small `PIP_WH`, 60-second auto-suspend, five-minute tasks, and a 20-credit monthly resource monitor (75% notice, 100% suspend). Views avoid materialized-table refresh costs, though complex reads will consume warehouse compute. At 100× volume, partition ingestion batches, use task graphs with retries and separate compute for transforms vs app, and materialize expensive marts. The optional stretch goals are intentionally omitted.

## Walkthrough

[10-minute speaking outline](docs/walkthrough.md). A recording requires the candidate's voice/account; the outline and runnable demo queries are provided for a live walkthrough.
