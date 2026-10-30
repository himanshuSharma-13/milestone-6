# Interview notes: PIP assessment quality analytics

## One-minute explanation

"I built a small Snowflake quality analytics platform using fabricated PIP-like cases. A Python script makes three CSV files with 3,200 cases and deliberate data problems. Snowflake loads them into RAW, then streams and scheduled tasks merge the latest records into STAGING. Views standardize labels, recalculate points, and quarantine bad records. CORE is a simple star schema, and MART contains QA KPIs, a stratified audit sample, an assessor funnel, and a transparent review scorecard. I added three roles, masking, a team row filter, and quality checks. I ran the SQL in Snowflake and compared the results with a local Python check. The scorecard supports human review only; it does not decide benefits or assessor performance."

## Explain the files in order

| File | What it does | Simple explanation |
|---|---|---|
| `scripts/generate_data.py` | Creates `cases.csv`, `activity_scores.csv`, and `people.csv` | Makes repeatable fake data, including known defects so quality checks have something to find. |
| `sql/00_setup_and_ingest.sql` | Creates the warehouse, resource monitor, schemas, stage, RAW tables, streams, and COPY commands | Loads the source files without transforming or losing the original rows. |
| `sql/01_pipeline.sql` | Creates three merge tasks, standardized and quarantine views, and CORE views | Keeps the latest record for each case/activity/person; checks dates, labels and points before a case reaches CORE. |
| `sql/02_marts_and_analytics.sql` | Creates KPI views, funnel, scorecard and audit sample procedure | Turns curated cases into review-ready measures and a reproducible sample. |
| `sql/03_security.sql` | Creates roles, grants, tags, masking and row access policy | Controls who can read identifiers and which team cases a viewer can see. |
| `sql/04_quality_tests.sql` | Runs source and curated quality queries | Shows that the deliberately bad source data is found and that CORE has zero key quality failures. |
| `sql/05_role_test.sql` | Runs the same queries under three primary roles | Demonstrates full, masked and team-limited access with real Snowflake results. |
| `app/streamlit_app.py` | Defines three dashboard views | Presents KPIs, at-risk open cases, assessor funnel and audit sample. The code exists; live app creation/verification remains to do. |
| `scripts/local_evidence.py` | Recomputes counts, sample and fairness example from CSVs | Provides an independent local comparison for the Snowflake output. |

## Data flow and key design choices

`CSV → internal stage → RAW → streams + 5-minute merge tasks → STAGING → CORE → MART → Streamlit`

- **Why three files?** They separate case decisions, 12 activity scores per case, and person/assessor details. The same case ID connects them.
- **Why COPY and tasks?** This is a three-file batch. COPY is easy to explain. Streams show new rows; tasks merge them into latest-row tables. `MERGE` makes repeated input safe at the business-key grain.
- **Why quarantine?** Cases with a missing required date, impossible date order, missing activity, or total points that disagree with activity scores should not silently affect KPIs. A recorded award band that disagrees with points stays in CORE as a QA exception because it needs human review.
- **What is the grain?** `CORE.FACT_CASE` is one valid case per row; `CORE.FACT_ACTIVITY_SCORE` is one case and activity per row. Dimensions describe claimant, assessor, region, assessment type and date.
- **What is SCD type 2 here?** `CORE.DIM_ASSESSOR` has effective-dated team versions. In the synthetic data assessor A001 changes team; a case joins the assessor version valid on its referral date. This is a small view-based demonstration, not a full production history loader.
- **Why views for CORE and MART?** They keep the implementation short and reflect the latest staged data. Expensive queries would need materialized tables or dynamic tables at larger scale.

## Results you can quote

These were observed in the signed-in Snowflake account on 30 October 2026:

| Check | Result |
|---|---:|
| RAW cases | 3,232 rows |
| Distinct source cases | 3,200 |
| RAW activity rows | 38,400 |
| RAW people rows | 3,200 |
| Duplicate source case IDs | 32 |
| Quarantined cases | 171 |
| Curated cases | 3,029 |
| Curated duplicate case IDs, invalid dates, labels and point mismatches | 0 each |
| Recorded band exceptions retained for QA | 50 |
| October audit sample | 44 of 55 eligible cases |
| Assessors outside 99.8% funnel limits | 0 |

The 171 quarantined cases break down locally as 73 points mismatches, 68 missing dates and 30 invalid date orders. The aggregate Snowflake count was verified; save the live reason-by-reason output before presenting that breakdown as independently verified in Snowflake.

**Role test:** `ASSESSMENT_ADMIN` and `QA_REVIEWER` each saw 3,029 cases across two teams; `ASSESSOR_TEAM_VIEWER`, mapped to TEAM_A, saw 1,487 cases in one team. The QA role saw masked name, NI number, birth date and health field on all 3,029 claimant rows. The team role could not query `CORE.DIM_CLAIMANT`. See `evidence/snowflake_role_test.md`.

## How to explain the analytics honestly

- **KPIs:** Award rates and points by component, region, assessor and assessment type; median and 90th percentile turnaround; mandatory reconsideration and appeal overturn rates; and open cases nearing a 40-day assumed target. Denominators are explicit in the SQL.
- **Audit sample:** For the selected decision month, the procedure partitions cases by region, assessment type, outcome and risk. It deterministically ranks cases with a fixed seed and samples 10% of base strata and 20% of high-risk strata, with `CEIL` giving at least one case per occupied stratum. It refuses to redraw a month that already has a sample. Because October has many small strata, 44 of 55 eligible cases were selected; do not describe this as a simple 10% sample.
- **Funnel:** Each assessor's observed daily-living award rate is compared with a rate expected from assessment type and condition mix. Limits widen for smaller caseloads. No assessor was outside the 99.8% limits in this synthetic run. An outlier would prompt case review, not a performance judgment.
- **Scorecard:** A hand-written heuristic raises review priority for points near thresholds, short narratives, long turnaround and band exceptions. The local held-out set had 160 challenged cases, precision 0.0556 and recall 0.0455. This is poor predictive performance, partly because challenge outcomes are mostly synthetic/random. Do not claim the model predicts overturns reliably. Snowflake's split uses a different hash, so its live precision/recall should be exported separately.
- **Fairness:** The local example shows North and South raw daily-living award rates of 87.65% and 75.82%. Weighting both to the same condition mix gives 80.81% and 80.39%. This illustrates confounding, not proof of fairness or bias. It is fabricated data and does not control for severity or all other factors.

## What is implemented, and what remains

**Implemented and exercised in Snowflake:** staged CSV ingestion; RAW/STAGING/CORE/MART objects; stream/task pipeline; quality and quarantine logic; KPIs; audit sample; funnel; scorecard SQL; roles, masking and row policy; observed case counts and role tests. The public repository contains source code and synthetic data.

**Built in code but not yet verified as a live Snowflake app:** the three-view Streamlit dashboard. Do not say the app is deployed until it has been created and opened successfully in Snowsight.

**Evidence still to collect:** Snowflake exports for quarantine reasons, scorecard evaluation/calibration, fairness, and the complete quality test table. Current local evidence includes some of those calculations, but it is labeled as a Python mirror. The project also has a ten-minute walkthrough outline, not a recorded video.

**Production limitations:** The type-2 dimension is a view over observed assignments; the audit table is protected from routine redraw by its procedure, but an owner could modify it directly; row access is applied to the exposed case view and should be rechecked for every new downstream object; retention/deletion is documented, not automated; five-minute tasks and X-Small warehouse are a demo cost setting, not measured production sizing. The synthetic scorecard must never make claimant decisions.

## Likely interview questions

**Why not dbt?** "I kept the project in numbered SQL files so each step is visible and easy to run in a trial account. dbt would be a good next step for lineage, tests and deployment when the project grows."

**How is it incremental?** "RAW append-only streams detect new rows, and scheduled tasks merge them into latest-row tables by business key. The downstream views then show the current staged state."

**How do you prove governance?** "I used the same query with secondary roles disabled under three primary roles. Admin saw all cases and identifiers, QA saw all cases with masked identifiers, and the team viewer saw only one team's cases and could not query claimant details."

**What would you improve first?** "Deploy and test the dashboard, automate quality assertions and evidence exports, make SCD2 event-driven, add task failure monitoring, and test every downstream view for row-policy leakage."
