"""
generate_demographics.py
─────────────────────────
Builds the demographic breakdown table (Race × Gender, plus Hispanic/Latino
counts) requested by IRB/journal reporting forms, for subjects included in
subject_list_preprocessed.csv.

Source columns (Prolific demographics, via combined_data_all.csv):
    Sex                     -> Gender  (Male / Female / Nonbinary+intersex)
    Ethnicity simplified    -> Race    (Prolific's "Ethnicity simplified"
                                         field is actually a coarse RACE
                                         category, not Hispanic/Latino
                                         ethnicity — see NOTE below)

NOTE on Hispanic/Latino origin
───────────────────────────────
The reporting form asks for a separate "Number of participants of Hispanic,
Latino/a, or Spanish origin" row, cross-tabulated by gender. Our current data
does NOT contain a Hispanic/Latino ethnicity field (only the race-like
"Ethnicity simplified" column). This script therefore:
    - always emits the Hispanic/Latino row, filled with 0s
    - prints/logs a WARNING that this data was not found
    - is written so that if a real Hispanic/Latino column becomes available
      later (e.g. from a supplementary Prolific export), you only need to
      set HISPANIC_COL below and the row will populate automatically.

Race mapping
─────────────
Prolific's "Ethnicity simplified" values are mapped onto the form's race
categories as follows. Prolific does not distinguish American Indian/Alaska
Native or Native Hawaiian/Pacific Islander from its other buckets, so those
rows will show 0 unless/until finer-grained data is available.

    White               -> White
    Black                -> Black or African American
    Asian                -> Asian
    Mixed                -> More than one race
    Other                -> Other
    Prefer not to say    -> Unknown
    CONSENT_REVOKED       -> Unknown
    DATA_EXPIRED          -> Unknown
    (missing / NaN)       -> Unknown

Gender mapping
───────────────
    Male                 -> Male
    Female                -> Female
    Prefer not to say    -> Nonbinary and/or intersex   [see WARNING below]
    CONSENT_REVOKED       -> Nonbinary and/or intersex   [see WARNING below]
    (missing / NaN)       -> Nonbinary and/or intersex   [see WARNING below]

The form only offers three gender columns (Male / Female / Nonbinary and/or
intersex), so anything that isn't cleanly Male/Female currently falls into
the third column as a catch-all. This is flagged with a WARNING at runtime
because "Prefer not to say" / "CONSENT_REVOKED" are not actually nonbinary
identities — it's a limitation of the form's fixed columns, not a claim
about those participants. Revisit if the form/collection changes.

Output
───────
Writes demographics_table.csv (Race x Gender counts + Hispanic/Latino row)
to PROJECT_ROOT, for the overall sample and, separately, one file per
country (demographics_table_<COUNTRY>.csv), since this is a 5-country study.

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
SUBJECT_LIST = SUBJECTS_DIR / "subject_list_preprocessed.csv"

print(f"[DEBUG] SUBJECTS_DIR = {SUBJECTS_DIR}")
print(f"[DEBUG] COMBINED_CSV = {COMBINED_CSV}")
print(f"[DEBUG] SUBJECT_LIST = {SUBJECT_LIST}")

# ── Column names / mappings ────────────────────────────────────────────────────
SEX_COL = "Sex"
RACE_COL = "Ethnicity simplified"   # Prolific's field name; it's actually race
# Set this to a real column name if/when Hispanic/Latino origin data becomes
# available (e.g. "Hispanic/Latino"). Left as None for now — see module
# docstring NOTE above.
HISPANIC_COL = None

GENDER_CATEGORIES = ["Male", "Female", "Nonbinary and/or intersex"]

GENDER_MAP = {
    "Male": "Male",
    "Female": "Female",
}  # anything else falls through to the nonbinary/intersex catch-all column

RACE_CATEGORIES = [
    "American Indian or Alaska Native",
    "Asian",
    "Black or African American",
    "Native Hawaiian or Pacific Islander",
    "White",
    "More than one race",
    "Unknown",
    "Other",
]

RACE_MAP = {
    "White": "White",
    "Black": "Black or African American",
    "Asian": "Asian",
    "Mixed": "More than one race",
    "Other": "Other",
    "Prefer not to say": "Unknown",
    "CONSENT_REVOKED": "Unknown",
    "DATA_EXPIRED": "Unknown",
}


def map_gender(raw: str) -> str:
    if pd.isna(raw):
        return "Nonbinary and/or intersex"
    return GENDER_MAP.get(raw.strip(), "Nonbinary and/or intersex")


def map_race(raw: str) -> str:
    if pd.isna(raw):
        return "Unknown"
    return RACE_MAP.get(raw.strip(), "Other")


def build_demographics_table(sub_df: pd.DataFrame, label: str) -> pd.DataFrame:
    """Build the Race x Gender count table (+ Hispanic/Latino row) for sub_df."""
    n = len(sub_df)
    print(f"\n[DEBUG] Building demographics table for '{label}' (n={n})")

    genders = sub_df[SEX_COL].apply(map_gender)
    races = sub_df[RACE_COL].apply(map_race)

    n_nonbinary_bucket = int((genders == "Nonbinary and/or intersex").sum())
    if n_nonbinary_bucket:
        print(f"[DEBUG] {n_nonbinary_bucket} subject(s) in '{label}' fell into the "
              f"'Nonbinary and/or intersex' column because their Sex value wasn't "
              f"'Male'/'Female' (includes missing, 'Prefer not to say', "
              f"'CONSENT_REVOKED'). See module docstring WARNING.")

    n_unknown_race = int((races == "Unknown").sum())
    if n_unknown_race:
        print(f"[DEBUG] {n_unknown_race} subject(s) in '{label}' mapped to race "
              f"'Unknown' (missing, 'Prefer not to say', 'CONSENT_REVOKED', or "
              f"'DATA_EXPIRED').")

    # Race x Gender counts
    table = pd.DataFrame(0, index=RACE_CATEGORIES, columns=GENDER_CATEGORIES)
    for race, gender in zip(races, genders):
        table.loc[race, gender] += 1

    # Hispanic/Latino row (placeholder unless HISPANIC_COL is set)
    hispanic_row = pd.Series(0, index=GENDER_CATEGORIES, name="Hispanic, Latino/a, or Spanish origin")
    if HISPANIC_COL is not None and HISPANIC_COL in sub_df.columns:
        is_hispanic = sub_df[HISPANIC_COL].astype(str).str.strip().str.lower().isin(
            ["yes", "true", "1", "hispanic", "latino", "latina", "latinx"]
        )
        for gender, is_h in zip(genders, is_hispanic):
            if is_h:
                hispanic_row[gender] += 1
    else:
        print(f"[WARNING] Ethnicity data not found: no Hispanic/Latino/Spanish-origin "
              f"column is available in the current data (HISPANIC_COL is unset). "
              f"The 'Hispanic, Latino/a, or Spanish origin' row for '{label}' is "
              f"being reported as all zeros as a placeholder. Set HISPANIC_COL at "
              f"the top of this script once that data is collected.")

    table = pd.concat([hispanic_row.to_frame().T, table])
    table.index.name = "Category"
    table.insert(0, "n_total", table[GENDER_CATEGORIES].sum(axis=1))

    return table


# ── Load subject list ──────────────────────────────────────────────────────────
print(f"\nLoading subject list: {SUBJECT_LIST}")
subj_df = pd.read_csv(SUBJECT_LIST)
included_subjects = set(subj_df["subject"].astype(str).str.strip())
print(f"  {len(included_subjects)} preprocessed subjects listed.")
print(f"[DEBUG] Subjects per country:\n{subj_df['country'].value_counts().to_string()}")

# ── Load combined data ─────────────────────────────────────────────────────────
print(f"\nLoading combined data: {COMBINED_CSV}")
df_raw = pd.read_csv(COMBINED_CSV, dtype=str)
print(f"[DEBUG] combined_data_all.csv shape (raw): {df_raw.shape}")

for required_col in (SEX_COL, RACE_COL):
    if required_col not in df_raw.columns:
        raise KeyError(f"Expected column '{required_col}' not found in {COMBINED_CSV}")

df = df_raw.copy()
df["ID"] = df["ID"].astype(str).str.strip()

df_all = df.copy()
df = df[df["ID"].isin(included_subjects)].copy()
n_dropped = len(df_all) - len(df)
print(f"\n  Rows in combined CSV           : {len(df_all)}")
print(f"  Rows matching preprocessed list: {len(df)}")
print(f"  Rows dropped (not in list)     : {n_dropped}")

missing_from_csv = included_subjects - set(df_all["ID"])
if missing_from_csv:
    print(f"[DEBUG] {len(missing_from_csv)} subject(s) in preprocessed list but NOT "
          f"found in combined CSV; they are excluded from the demographics table.")

# ── Output folder ────────────────────────────────────────────────────────────────
OUTPUT_DIR = PROJECT_ROOT / "demographics"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
print(f"[DEBUG] OUTPUT_DIR = {OUTPUT_DIR}")

# ── Overall table ───────────────────────────────────────────────────────────────
overall_table = build_demographics_table(df, "overall")
out_path = OUTPUT_DIR / "demographics_table.csv"
overall_table.to_csv(out_path)
print(f"\n[DEBUG] Overall demographics table:\n{overall_table.to_string()}")
print(f"Overall table written to {out_path}")

# ── Per-country tables ───────────────────────────────────────────────────────────
if "country" in df.columns:
    for country in sorted(df["country"].dropna().unique()):
        country_df = df[df["country"] == country]
        country_table = build_demographics_table(country_df, country)
        country_out_path = OUTPUT_DIR / f"demographics_table_{country}.csv"
        country_table.to_csv(country_out_path)
        print(f"[DEBUG] {country} table written to {country_out_path}")
else:
    print("[WARNING] No 'country' column found; skipping per-country breakdown.")

print("\nDone.")