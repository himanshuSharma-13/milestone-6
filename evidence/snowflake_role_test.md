# Observed Snowflake role test — 30 October 2026

Account: Snowflake Enterprise trial. Test user mapped to `TEAM_A` in `PIP_QUALITY.SECURITY.USER_TEAMS`. `USE SECONDARY ROLES NONE` was set for each query.

The same query was run under each primary role:

```sql
SELECT CURRENT_ROLE() AS role_name, COUNT(*) AS visible_cases,
       COUNT(DISTINCT team_id) AS visible_teams
FROM PIP_QUALITY.CORE.FACT_CASE;
```

| Role | Visible cases | Visible teams |
|---|---:|---:|
| `ASSESSMENT_ADMIN` | 3,029 | 2 |
| `QA_REVIEWER` | 3,029 | 2 |
| `ASSESSOR_TEAM_VIEWER` | 1,487 | 1 |

Masking was tested with `COUNT_IF(claimant_name='REDACTED')`, the same predicate for NI number and health condition, and `COUNT_IF(date_of_birth IS NULL)` on `CORE.DIM_CLAIMANT`:

| Role | Claimants | Names masked | NI masked | DOB masked | Health masked |
|---|---:|---:|---:|---:|---:|
| `ASSESSMENT_ADMIN` | 3,029 | 0 | 0 | 0 | 0 |
| `QA_REVIEWER` | 3,029 | 3,029 | 3,029 | 3,029 | 3,029 |

Under `ASSESSOR_TEAM_VIEWER`, a direct `SELECT` on `CORE.DIM_CLAIMANT` failed with `Object 'PIP_QUALITY.CORE.DIM_CLAIMANT' does not exist or not authorized`, as intended. The test user has no direct grant on that view. These are observed Snowsight results, not local simulations.
