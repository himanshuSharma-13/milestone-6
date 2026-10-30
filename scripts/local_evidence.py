"""Local smoke evidence for generated CSVs; Snowflake SQL remains the source of truth."""
import csv
import hashlib
import json
import math
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "evidence"
OUT.mkdir(exist_ok=True)

def rows(name):
    with (DATA / name).open(newline="") as f:
        return list(csv.DictReader(f))

def band(p):
    return "ENHANCED" if p >= 12 else "STANDARD" if p >= 8 else "NO_AWARD"

def normalize(s):
    return {"enhanced": "ENHANCED", "enh": "ENHANCED", "enhanced rate": "ENHANCED",
            "standard": "STANDARD", "std": "STANDARD", "standard rate": "STANDARD",
            "no award": "NO_AWARD", "none": "NO_AWARD"}.get(s.lower())

raw = rows("cases.csv")
people = {x["case_id"]: x for x in rows("people.csv")}
activities = defaultdict(dict)
for x in rows("activity_scores.csv"):
    activities[x["case_id"]][x["activity"]] = (x["component"], int(x["points"]))
latest = {x["case_id"]: x for x in raw}
reasons = Counter()
valid = []
for c in latest.values():
    a = activities[c["case_id"]]
    totals = {k: sum(p for comp, p in a.values() if comp == k) for k in ("DL", "MOB")}
    referral = date.fromisoformat(c["referral_date"])
    decision = date.fromisoformat(c["decision_date"]) if c["decision_date"] else None
    reason = ("MISSING_DATE" if not c["assessment_date"] or (c["status"] == "CLOSED" and not decision)
              else "DATE_ORDER" if decision and decision < referral
              else "INVALID_LABEL" if c["status"] == "CLOSED" and (not normalize(c["dl_decision"]) or not normalize(c["mob_decision"]))
              else "MISSING_ACTIVITY" if len(a) != 12
              else "POINTS_MISMATCH" if totals["DL"] != int(c["dl_points"]) or totals["MOB"] != int(c["mob_points"])
              else None)
    if reason:
        reasons[reason] += 1
        continue
    c = dict(c, **{"dl_decision": normalize(c["dl_decision"]) if c["status"] == "CLOSED" else "",
                   "mob_decision": normalize(c["mob_decision"]) if c["status"] == "CLOSED" else "",
                   "team_id": people[c["case_id"]]["team_id"],
                   "band_exception": int(c["status"] == "CLOSED" and
                      (normalize(c["dl_decision"]) != band(totals["DL"]) or
                       normalize(c["mob_decision"]) != band(totals["MOB"]))),
                   "turnaround_days": (decision - referral).days if decision else None})
    valid.append(c)
closed = [c for c in valid if c["status"] == "CLOSED"]
raw_duplicate_ids = sum(n > 1 for n in Counter(c["case_id"] for c in raw).values())
quality = {"raw_rows": len(raw), "distinct_cases": len(latest),
           "raw_duplicate_case_ids": raw_duplicate_ids,
           "raw_missing_assessment_dates": sum(not c["assessment_date"] for c in raw),
           "raw_decisions_before_referral": sum(bool(c["decision_date"]) and c["decision_date"] < c["referral_date"] for c in raw),
           "quarantine_by_reason": dict(reasons), "curated_cases": len(valid),
           "curated_duplicate_case_ids": len(valid) - len({c["case_id"] for c in valid}),
           "curated_invalid_dates": sum(not c["assessment_date"] or
                (c["status"] == "CLOSED" and not c["decision_date"]) or
                (bool(c["decision_date"]) and c["decision_date"] < c["referral_date"]) for c in valid),
           "curated_invalid_labels": sum(c["status"] == "CLOSED" and
                (c["dl_decision"] not in ("NO_AWARD","STANDARD","ENHANCED") or
                 c["mob_decision"] not in ("NO_AWARD","STANDARD","ENHANCED")) for c in valid)}

month = date(2026, 10, 1)
eligible = [c for c in closed if c["decision_date"].startswith("2026-10")]
strata = defaultdict(list)
for c in eligible:
    risk = int(any(abs(int(c["dl_points"]) - x) <= 2 or abs(int(c["mob_points"]) - x) <= 2 for x in (8,12))
               or c["band_exception"] or int(c["narrative_words"]) < 40 or c["turnaround_days"] > 40)
    strata[(c["region"],c["assessment_type"],c["dl_decision"],risk)].append(c)
sample = []
for key, group in strata.items():
    group.sort(key=lambda c: hashlib.sha256(f"PIP_AUDIT_V1|{month}|{c['case_id']}".encode()).hexdigest())
    for c in group[:math.ceil(len(group) * (0.20 if key[3] else 0.10))]:
        sample.append({"sample_month": str(month), "case_id": c["case_id"], "region": key[0],
                       "assessment_type": key[1], "outcome": key[2], "risk_flag": key[3],
                       "rationale": "20% high-risk stratum" if key[3] else "10% base stratum",
                       "seed": "PIP_AUDIT_V1"})
with (OUT / "local_sample_example.csv").open("w",newline="") as f:
    writer = csv.DictWriter(f, fieldnames=sample[0].keys())
    writer.writeheader(); writer.writerows(sample)

def rate(group):
    return sum(c["dl_decision"] != "NO_AWARD" for c in group)/len(group) if group else None

# Direct standardization by condition category over the pooled condition mix.
pooled_mix = Counter(c["condition_category"] for c in closed)
region_rates = {}
for region in sorted({c["region"] for c in closed}):
    group = [c for c in closed if c["region"] == region]
    standardized = sum((pooled_mix[k]/len(closed)) * rate([c for c in group if c["condition_category"] == k]) for k in pooled_mix)
    region_rates[region] = {"n": len(group), "raw_daily_living_award_rate": round(rate(group),4),
                            "condition_standardized_rate": round(standardized,4),
                            "mental_health_share": round(sum(c["condition_category"] == "mental health" for c in group)/len(group),4)}

challenge = [c for c in closed if c["mr_flag"] == "1" or c["appeal_flag"] == "1"]
heldout = [c for c in challenge if int(hashlib.sha256(c["case_id"].encode()).hexdigest(),16)%5 == 0]
def score(c):
    p = .04
    if any(abs(int(c[f"{prefix}_points"]) - x) <= 2 for prefix in ("dl","mob") for x in (8,12)): p += .12
    if int(c["narrative_words"]) < 40: p += .12
    if c["turnaround_days"] > 40: p += .10
    if c["band_exception"]: p += .20
    return min(.9,p)
tp = sum(score(c)>=.25 and (c["mr_overturned"] == "1" or c["appeal_overturned"] == "1") for c in heldout)
pred = sum(score(c)>=.25 for c in heldout)
actual = sum(c["mr_overturned"] == "1" or c["appeal_overturned"] == "1" for c in heldout)
model = {"heldout_n":len(heldout), "precision": round(tp/pred,4) if pred else None,
         "recall":round(tp/actual,4) if actual else None,
         "mean_predicted":round(sum(map(score,heldout))/len(heldout),4),
         "observed_rate":round(actual/len(heldout),4)}
evidence = {"source":"local Python mirror of generated CSVs; Snowflake execution unverified",
            "quality":quality, "audit_sample":{"month":str(month),"eligible":len(eligible),"selected":len(sample),
            "high_risk_selected":sum(x["risk_flag"] for x in sample)},
            "role_test_expected":{"admin_cases":len(valid),"qa_cases":len(valid),
              "team_a_cases":sum(c["team_id"] == "TEAM_A" for c in valid),
              "team_b_cases":sum(c["team_id"] == "TEAM_B" for c in valid)},
            "region_fairness":region_rates,"scorecard_heldout":model,
            "band_exceptions":sum(c["band_exception"] for c in closed)}
(OUT / "local_results.json").write_text(json.dumps(evidence,indent=2)+"\n")
print(json.dumps(evidence,indent=2))
