# Ten-minute live walkthrough script

| Time | Show | Explain |
|---|---|---|
| 0:00–1:00 | README diagrams | Synthetic-only QA platform; no automated benefit or assessor decisions. |
| 1:00–2:00 | Three CSVs and generator | 3,200 cases, 12 activity rows each, deliberate defects. |
| 2:00–3:00 | `00` and `01` SQL | Stage/COPY, streams/tasks, dedupe, normalized labels, quarantine. |
| 3:00–4:00 | CORE views and dictionary | Fact grains, dimensions, assessor A001 team change. |
| 4:00–5:00 | KPI views and app overview | Award rates, mean points, turnaround, overturns, open caseload. |
| 5:00–6:00 | Security SQL and role test | Masked identifiers and team row filter; run actual role queries. |
| 6:00–7:00 | Quality tests and local results | Explain 171 quarantined cases and band exceptions retained for review. |
| 7:00–8:00 | Audit sample and funnel | Reproducible stratified draw, risk oversample, case-mix adjusted limits. |
| 8:00–9:00 | Scorecard and fairness note | Poor held-out model metrics, raw vs standardized region rates. |
| 9:00–10:00 | README cost/retention | X-Small warehouse, monitor, access history, deletion process, next steps. |

Before recording: run the Snowflake scripts, capture real quality and role-test output, and refresh the app. If a trial account is unavailable, present the checked-in local evidence and explicitly say Snowflake execution has not been verified.
