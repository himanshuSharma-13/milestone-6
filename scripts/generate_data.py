"""Deterministic, wholly synthetic CSVs. Run: python scripts/generate_data.py."""
import csv
import random
from datetime import date, timedelta
from pathlib import Path

R = random.Random(20261029)
OUT = Path(__file__).resolve().parents[1] / "data"
OUT.mkdir(exist_ok=True)
REGIONS = ["North", "South", "East", "West"]
TYPES = ["face-to-face", "telephone", "video", "paper"]
CONDITIONS = ["musculoskeletal", "mental health", "neurological", "other"]
FIRST = ["Alex", "Sam", "Jordan", "Taylor", "Casey", "Morgan", "Jamie", "Robin"]
LAST = ["Smith", "Patel", "Jones", "Brown", "Ali", "Khan", "Wilson", "Clark"]
ACTIVITIES = [("DL", f"DL{i:02d}") for i in range(1, 11)] + [("MOB", "MOB01"), ("MOB", "MOB02")]

def band(points):
    return "ENHANCED" if points >= 12 else "STANDARD" if points >= 8 else "NO_AWARD"

def label(value):
    return R.choice({"ENHANCED": ["Enhanced", "ENH", "enhanced rate"],
                     "STANDARD": ["Standard", "STD", "standard rate"],
                     "NO_AWARD": ["No award", "NONE", "no award"]}[value])

cases, scores, people = [], [], []
start = date(2025, 1, 1)
for n in range(1, 3201):
    case_id = f"C{n:05d}"
    assessor_id = f"A{1 + (n * 17) % 40:03d}"
    claimant_id = f"P{n:05d}"
    referral = start + timedelta(days=R.randrange(628))
    assessment = referral + timedelta(days=R.randrange(2, 25))
    decision = min(date(2026, 10, 30), assessment + timedelta(days=R.randrange(1, 18)))
    region = R.choice(REGIONS)
    assessment_type = R.choice(TYPES)
    condition = R.choices(CONDITIONS,
        [1, 6 if region == "North" else 1, 1, 1] if region == "North" else
        [1, 1 if region == "South" else 2, 1, 2])[0]
    activity_points = {}
    for component, activity in ACTIVITIES:
        weights = [0.52, 0.25, 0.14, 0.07, 0.02] if condition == "mental health" and component == "DL" else [0.68, 0.19, 0.09, 0.035, 0.005]
        points = R.choices([0, 2, 4, 8, 12], weights)[0]
        activity_points[component] = activity_points.get(component, 0) + points
        scores.append([case_id, component, activity, points])
    dl, mob = activity_points["DL"], activity_points["MOB"]
    # Seed a modest number of deliberate quality exceptions.
    reported_dl = dl + (2 if n % 43 == 0 else 0)
    reported_mob = mob
    dl_band = band(dl)
    mob_band = band(mob)
    if n % 59 == 0:
        dl_band = "STANDARD" if dl_band != "STANDARD" else "ENHANCED"
    is_open = n % 19 == 0
    mr = n % 5 == 0 and not is_open
    appeal = n % 13 == 0 and not is_open
    mr_overturned = int(mr and R.random() < (0.27 if n % 7 == 0 else 0.12))
    appeal_overturned = int(appeal and R.random() < 0.17)
    row = [case_id, claimant_id, assessor_id, region, assessment_type,
           referral.isoformat(), "" if n % 47 == 0 else assessment.isoformat(),
           "" if is_open else ((referral - timedelta(days=2)).isoformat() if n % 101 == 0 else decision.isoformat()),
           reported_dl, reported_mob, "" if is_open else label(dl_band), "" if is_open else label(mob_band),
           int(mr), mr_overturned, int(appeal), appeal_overturned,
           "OPEN" if is_open else "CLOSED", R.randrange(1, 6),
           R.randrange(20, 101), condition, assessment_type]
    cases.append(row)
    team = "TEAM_B" if assessor_id == "A001" and referral >= date(2026, 1, 1) else ("TEAM_A" if int(assessor_id[1:]) % 2 else "TEAM_B")
    people.append([case_id, claimant_id, R.choice(FIRST) + " " + R.choice(LAST),
                   f"QQ{n % 1000000:06d}C", (date(1945, 1, 1) + timedelta(days=R.randrange(22000))).isoformat(),
                   condition, assessor_id, f"Assessor {assessor_id}", team, region,
                   referral.isoformat()])

# A later duplicate wins. Duplicate is intentional, even if values are unchanged.
for n in range(1, 33):
    cases.append(cases[n - 1].copy())

def write(name, header, rows):
    with (OUT / name).open("w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(header)
        writer.writerows(rows)

write("cases.csv", ["case_id", "claimant_id", "assessor_id", "region", "assessment_type",
    "referral_date", "assessment_date", "decision_date", "dl_points", "mob_points",
    "dl_decision", "mob_decision", "mr_flag", "mr_overturned", "appeal_flag",
    "appeal_overturned", "status", "audit_quality_score", "narrative_words",
    "condition_category", "source_type"], cases)
write("activity_scores.csv", ["case_id", "component", "activity", "points"], scores)
write("people.csv", ["case_id", "claimant_id", "claimant_name", "ni_number", "date_of_birth",
    "health_condition", "assessor_id", "assessor_name", "team_id", "region", "valid_from"], people)
print(f"Generated {len(cases)} case rows ({3200} distinct), {len(scores)} activity rows, {len(people)} people rows in {OUT}")
