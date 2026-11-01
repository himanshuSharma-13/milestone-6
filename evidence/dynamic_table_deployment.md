# Snowflake deployment check — 1 November 2026

Account: `ap-southeast-7.aws/tp38335`; role: `ACCOUNTADMIN`; warehouse: `PIP_WH`.

The old stream/task objects and obsolete MART views were removed with `sql/migrate_existing_pipeline.sql`. Then `01_pipeline.sql`, `02_marts_and_analytics.sql`, and `03_security.sql` completed in Snowsight. The saved `01` and `02` worksheets were updated to match the repository SQL.

| Check | Snowflake result |
| --- | ---: |
| RAW.CASES rows | 3,232 |
| RAW.ACTIVITY_SCORES rows | 38,400 |
| RAW.PEOPLE rows | 3,200 |
| STAGING.CASES_LATEST rows | 3,200 |
| STAGING.ACTIVITY_LATEST rows | 38,400 |
| STAGING.PEOPLE_LATEST rows | 3,200 |
| CORE.FACT_CASE rows | 3,029 |
| MART views | 6 |
| Existing October audit sample rows | 44 |

`SHOW DYNAMIC TABLES IN SCHEMA PIP_QUALITY.STAGING` reported all three tables in `INCREMENTAL` refresh mode with a `1 hour` target lag. The `sql/04_quality_tests.sql` checks returned 0 for invalid standardized labels, duplicate fact case IDs, curated points mismatches, and invalid curated dates. Expected raw defects remained: 32 duplicate case IDs, 68 missing assessment dates, 30 invalid date orders, and 73 points mismatches in quarantine.

The synthetic data ends in October 2026, so running the current-month audit procedure on 1 November creates no new sample rows. The dashboard displays the latest available October sample. A live Streamlit app and role-specific access checks were not verified in this deployment.
