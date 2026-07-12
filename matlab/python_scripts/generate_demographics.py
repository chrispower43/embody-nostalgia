"""
generate_demographics.py
─────────────────────────
Builds a per-country demographic summary (Gender breakdown, Race breakdown,
Age mean/SD, and a Consent Revoked count), run separately for the
preprocessed (paired) subject group and the unfiltered subject group.

Output
───────
One CSV per cohort, written directly into PROJECT_ROOT/demographics/:

    demographics/demographics_preprocessed.csv
    demographics/demographics_unfiltered.csv

Columns are countries (plus a "Total" column). Rows are:
    Male / Female / Nonbinary and/or intersex / Prefer not to say
                                                  (gender breakdown)
    White / Black or African American / Asian / More than one race / Other /
    Prefer not to say / Data Expired              (race breakdown)
    Age, Mean (SD)
    Consent Revoked                              (count excluded from
                                                   everything above)

Gender and race are NOT cross-tabulated against each other — each is a
simple per-country breakdown, independent of the other.

Source columns (Prolific demographics, via combined_data_all.csv):
    Sex                     -> Gender
    Ethnicity simplified    -> Race   (Prolific's "Ethnicity simplified"
                                        field is actually a coarse RACE
                                        category, not Hispanic/Latino
                                        ethnicity)
    Age                      -> Age

Consent Revoked handling
──────────────────────────
A subject is treated as "Consent Revoked" if their Sex OR Ethnicity
simplified value is literally "CONSENT_REVOKED". Those subjects are
excluded from the Gender rows, Race rows, and the Age mean/SD, and are
instead counted once in the dedicated "Consent Revoked" row.

Unmapped / unexpected values
──────────────────────────────
Male/Female/Nonbinary and/or intersex/Prefer not to say (gender) and
White/Black/Mixed/Asian/Other/Prefer not to say/DATA_EXPIRED (race) are
mapped to output rows (Prolific's raw "Black"/"Mixed" values map to
"Black or African American"/"More than one race" respectively). Any other
raw value (anything new/unexpected) does NOT get silently bucketed
anywhere — instead, the subject's ID and the offending raw value are
printed to the console so the mapping can be extended deliberately, and
that subject is excluded from the relevant row's count (gender, race, or
age) until the code is updated.

NOTE on Hispanic/Latino origin
───────────────────────────────
Our current data does not contain a Hispanic/Latino ethnicity field
(only the race-like "Ethnicity simplified" column), so no such row is
produced. Revisit if/when that data becomes available.

Usage:
    python generate_demographics.py
    python python_scripts/generate_demographics.py   # or via MATLAB pyrunfile()
"""

import os
import sys
import numpy as np
import pandas as pd
from pathlib import Path

# ── Locate project root & load config ─────────────────────────────────────────
# Same pattern as analyse_ratings.py: __file__ is unavailable under MATLAB's
# pyrunfile(), so EMBODY_PROJECT_ROOT must be set explicitly by the caller.
#   py.os.environ().update(py.dict(pyargs('EMBODY_PROJECT_ROOT', project_root)))
_project_root = os.environ.get("EMBODY_PROJECT_ROOT")
if not _project_root:
    raise RuntimeError(
        "EMBODY_PROJECT_ROOT is not set. This script cannot infer its own "
        "location when run via pyrunfile(), so the caller must set this "
        "environment variable explicitly before invoking generate_demographics.py.\n"
        "From MATLAB, set it via:\n"
        "  py.os.environ().update(py.dict(pyargs('EMBODY_PROJECT_ROOT', project_root)))"
    )
PROJECT_ROOT = Path(_project_root)

print(f"[DEBUG] PROJECT_ROOT = {PROJECT_ROOT}")

sys.path.insert(0, str(PROJECT_ROOT / "config"))
from config_loader import load_config

cfg = load_config(PROJECT_ROOT / "config" / "config.toml")

SUBJECTS_DIR = cfg.subjects_dir
COMBINED_CSV = cfg.combined_csv

print(f"[DEBUG] SUBJECTS_DIR = {SUBJECTS_DIR}")
print(f"[DEBUG] COMBINED_CSV = {COMBINED_CSV}")

# ── Column names / mappings ────────────────────────────────────────────────────
SEX_COL = "Sex"
RACE_COL = "Ethnicity simplified"   # Prolific's field name; it's actually race
AGE_COL = "Age"

CONSENT_REVOKED_VALUE = "CONSENT_REVOKED"

# NOTE: Gender and race each have their own "Prefer not to say" option, but they
# are DIFFERENT survey questions (Sex vs. Ethnicity simplified). Previously both
# used the identical string "Prefer not to say" as their row/dict key, which is
# a genuine bug: ROW_ORDER = GENDER_ROWS + RACE_ROWS was used to build a single
# `counts` dict via `{row: 0 for row in ROW_ORDER}`, and since a dict cannot hold
# two entries with the same key, the gender-PNTS and race-PNTS counts silently
# accumulated into ONE shared slot. That shared slot was then included in BOTH
# `sum(counts[r] for r in GENDER_ROWS)` and `sum(counts[r] for r in RACE_ROWS)`,
# inflating both totals by however many subjects had Sex == "Prefer not to say"
# or Race == "Prefer not to say" (or both). This is why gender_total and
# race_total could disagree, or even both come out too high, whenever a cohort
# contained a "Prefer not to say" value on either field.
#
# Fix: use distinct internal keys for the two "Prefer not to say" rows so they
# never share a dict slot. The printed/CSV row label still says "Prefer not to
# say" for both, but a "(Gender)" / "(Race)" suffix distinguishes them so it's
# clear at a glance which question each row is summarizing.
GENDER_PNTS_LABEL = "Prefer not to say (Gender)"
RACE_PNTS_LABEL = "Prefer not to say (Race)"

GENDER_ROWS = ["Male", "Female", "Nonbinary and/or intersex", GENDER_PNTS_LABEL]
GENDER_MAP = {
    "Male": "Male",
    "Female": "Female",
    "Nonbinary and/or intersex": "Nonbinary and/or intersex",
    "Prefer not to say": GENDER_PNTS_LABEL,
}

RACE_ROWS = ["White", "Black or African American", "Asian", "More than one race", "Other",
             RACE_PNTS_LABEL, "Data Expired"]
RACE_MAP = {
    "White": "White",
    "Black": "Black or African American",
    "Asian": "Asian",
    "Mixed": "More than one race",
    "Other": "Other",
    "Prefer not to say": RACE_PNTS_LABEL,
    "DATA_EXPIRED": "Data Expired",
}

AGE_ROW_LABEL = "Age, Mean (SD)"
CONSENT_REVOKED_ROW_LABEL = "Consent Revoked"

ROW_ORDER = GENDER_ROWS + RACE_ROWS + [AGE_ROW_LABEL, CONSENT_REVOKED_ROW_LABEL]


def flag_unmapped(subject_id: str, field_name: str, raw_value) -> None:
    print(f"[FLAG] Subject '{subject_id}': {field_name} = {raw_value!r} does not map "
          f"to a known category and was excluded from that row. Update the mapping "
          f"in generate_demographics.py if this value should be accommodated.")


def build_country_column(df: pd.DataFrame, label: str) -> pd.Series:
    """Build one column (Series indexed by ROW_ORDER) of counts/stats for df."""
    is_consent_revoked = (df[SEX_COL] == CONSENT_REVOKED_VALUE) | (df[RACE_COL] == CONSENT_REVOKED_VALUE)
    n_consent_revoked = int(is_consent_revoked.sum())

    counts = {row: 0 for row in ROW_ORDER}
    counts[CONSENT_REVOKED_ROW_LABEL] = n_consent_revoked

    remaining = df[~is_consent_revoked]

    # Gender breakdown
    for _, row in remaining.iterrows():
        raw = row[SEX_COL]
        if pd.isna(raw):
            flag_unmapped(row["ID"], SEX_COL, raw)
            continue
        mapped = GENDER_MAP.get(raw.strip())
        if mapped is None:
            flag_unmapped(row["ID"], SEX_COL, raw)
            continue
        counts[mapped] += 1

    # Race breakdown
    for _, row in remaining.iterrows():
        raw = row[RACE_COL]
        if pd.isna(raw):
            flag_unmapped(row["ID"], RACE_COL, raw)
            continue
        mapped = RACE_MAP.get(raw.strip())
        if mapped is None:
            flag_unmapped(row["ID"], RACE_COL, raw)
            continue
        counts[mapped] += 1

    # Age mean (SD)
    ages = pd.to_numeric(remaining[AGE_COL], errors="coerce")
    for subj_id, raw_age, parsed_age in zip(remaining["ID"], remaining[AGE_COL], ages):
        if pd.isna(parsed_age) and not pd.isna(raw_age):
            flag_unmapped(subj_id, AGE_COL, raw_age)
    if ages.notna().sum() > 0:
        age_mean = ages.mean()
        age_sd = ages.std(ddof=1) if ages.notna().sum() > 1 else float("nan")
        counts[AGE_ROW_LABEL] = f"{age_mean:.1f} ({age_sd:.1f})"
    else:
        counts[AGE_ROW_LABEL] = "n/a"

    print(f"[DEBUG] '{label}' — n={len(df)}, consent revoked={n_consent_revoked}, "
          f"gender total={sum(counts[r] for r in GENDER_ROWS)}, "
          f"race total={sum(counts[r] for r in RACE_ROWS)}")

    return pd.Series(counts, index=ROW_ORDER, name=label)


def run_demographics_for_list(subject_list_path: Path, label: str, out_path: Path) -> None:
    """Filter combined data to subject_list_path's IDs, build the per-country
    summary table, and write it to out_path."""
    print("\n" + "=" * 75)
    print(f"  Running demographics for '{label}' group")
    print(f"  Subject list: {subject_list_path}")
    print("=" * 75)

    if not subject_list_path.exists():
        print(f"[WARNING] Subject list not found: {subject_list_path}. Skipping '{label}'.")
        return

    subj_df = pd.read_csv(subject_list_path)
    included_subjects = set(subj_df["subject"].astype(str).str.strip())
    print(f"  {len(included_subjects)} '{label}' subjects listed.")

    df = df_raw[df_raw["ID"].isin(included_subjects)].copy()
    n_dropped = len(df_raw) - len(df)
    print(f"\n  Rows in combined CSV       : {len(df_raw)}")
    print(f"  Rows matching '{label}' list: {len(df)}")
    print(f"  Rows dropped (not in list) : {n_dropped}")

    missing_from_csv = included_subjects - set(df_raw["ID"])
    if missing_from_csv:
        print(f"[DEBUG] {len(missing_from_csv)} subject(s) in '{label}' list but NOT "
              f"found in combined CSV; they are excluded from the demographics table.")

    if "country" not in df.columns:
        print(f"[WARNING] No 'country' column found; cannot build per-country table for '{label}'.")
        return

    columns = []
    for country in sorted(df["country"].dropna().unique()):
        country_df = df[df["country"] == country]
        columns.append(build_country_column(country_df, country))
    columns.append(build_country_column(df, "Total"))

    table = pd.concat(columns, axis=1)
    table.index.name = "Category"
    table.to_csv(out_path)
    print(f"\n[DEBUG] '{label}' demographics table:\n{table.to_string()}")
    print(f"'{label}' table written to {out_path}")


# ── Output folder ────────────────────────────────────────────────────────────────
OUTPUT_DIR = PROJECT_ROOT / "demographics"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
print(f"[DEBUG] OUTPUT_DIR = {OUTPUT_DIR}")

# ── Load combined data (once — shared across both subject lists) ──────────────
print(f"\nLoading combined data: {COMBINED_CSV}")
df_raw = pd.read_csv(COMBINED_CSV, dtype=str)
print(f"[DEBUG] combined_data_all.csv shape (raw): {df_raw.shape}")

for required_col in (SEX_COL, RACE_COL, AGE_COL):
    if required_col not in df_raw.columns:
        raise KeyError(f"Expected column '{required_col}' not found in {COMBINED_CSV}")

df_raw["ID"] = df_raw["ID"].astype(str).str.strip()

SUBJECT_LIST_PREPROCESSED = SUBJECTS_DIR / "subject_list_preprocessed.csv"
SUBJECT_LIST_UNFILTERED = SUBJECTS_DIR / "subject_list_unfiltered.csv"

run_demographics_for_list(SUBJECT_LIST_PREPROCESSED, "preprocessed", OUTPUT_DIR / "demographics_preprocessed.csv")
run_demographics_for_list(SUBJECT_LIST_UNFILTERED, "unfiltered", OUTPUT_DIR / "demographics_unfiltered.csv")

print("\nDone.")