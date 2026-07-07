"""
build_combined_data.py
──────────────────────
Builds combined_data_all.csv by:
  1. Reading subject lists from final&new_subjects/<country>/all_preprocessed/
  2. Filtering each country's Qualtrics CSV to only those subjects
  3. Merging in demographic data from Prolific CSVs
  4. Cleaning / reshaping rating columns
  5. Computing SNS, BMRQ, and SES composite scores
  6. Writing combined_data_all.csv to the project root

Expected folder layout (relative to this script / the MATLAB project root):
  qualtrics_data/
      BR.csv  IN.csv  JP.csv  SP.csv  US.csv
  prolific_data/
      BR prolific.csv  IN prolific.csv  JP prolific.csv
      SP prolific.csv  US prolific.csv
  final&new_subjects/
      <country>/all_preprocessed/   ← .mat files live here

Output:
  combined_data_all.csv             ← written to project root

Usage from MATLAB:
  pyrunfile("build_combined_data.py")
"""

import re
import numpy as np
import pandas as pd

# ── Paths ─────────────────────────────────────────────────────────────────────
import os, sys
from pathlib import Path

print("DEBUG (python): EMBODY_PROJECT_ROOT =", os.environ.get("EMBODY_PROJECT_ROOT", "NOT SET"))

# Allow running standalone (outside MATLAB) by falling back to script location
_project_root = os.environ.get("EMBODY_PROJECT_ROOT")
if _project_root:
    PROJECT_ROOT = Path(_project_root)
else:
    PROJECT_ROOT = Path(__file__).parent.parent  # python_scripts/ -> project root

sys.path.insert(0, str(PROJECT_ROOT / "config"))
from config_loader import load_config

cfg = load_config(PROJECT_ROOT / "config" / "config.toml")  # explicit path, no __file__

PROJECT_ROOT  = cfg.subjects_dir.parent   # config.toml lives in project root
QUALTRICS_DIR = cfg.qualtrics_data
PROLIFIC_DIR  = cfg.prolific_data
SUBJECTS_ROOT = cfg.subjects_dir
OUTPUT_CSV    = cfg.combined_csv
COUNTRIES     = cfg.countries


# ── Step 1: collect processed subject IDs from .mat file names ────────────────
print("Scanning all_preprocessed directories for subject IDs...")
subjects_by_country: dict[str, list[str]] = {}

subjects_source_dir = SUBJECTS_ROOT / "all" / "subjects"
all_subject_ids: list[str] = []
if subjects_source_dir.exists():
    for entry in sorted(subjects_source_dir.iterdir()):
        if entry.is_dir() and not entry.name.startswith("."):
            all_subject_ids.append(f"R_{entry.name}")

# Then use all_subject_ids for every country (Qualtrics filter handles country assignment)
for country in COUNTRIES + ["all"]:
    subjects_by_country[country] = all_subject_ids
processed_subjects = set(all_subject_ids)

print(f"\nTotal unique processed subjects: {len(processed_subjects)}")


# ── Step 2: column definitions ───────────────────────────────────────────────

# SNS (Southampton Nostalgia Scale): 6 numeric items + 1 frequency item (Q478)
SNS_NUMERIC_COLS = ["Q472_1", "Q472_2", "Q472_3", "Q472_4", "Q472_5", "Q472_6"]
SNS_FREQ_COL = "Q478"

# BMRQ (Barcelona Music Reward Questionnaire): 20 items, 1-5 scale
BMRQ_COLS = [f"BMRQ_{i}" for i in range(1, 21)]

# SES (subjective socioeconomic status): two 10-rung on/off ladders
SES_COUNTRY_COLS   = [f"SES1_{i}" for i in range(1, 11)]
SES_COMMUNITY_COLS = [f"SES2_{i}" for i in range(1, 11)]

COLUMNS_TO_KEEP = [
    "ResponseId", "PROLIFIC_PID",
    # Nostalgia songs
    "N1_nost", "N1_pos_13", "N1_neg_10", "N1_act_10", "N1_deact_10", "N1_enjoy",
    "N2_nost", "N2_pos_10", "N2_neg_10", "N2_act_10", "N2_deact_10", "N2_enjoy",
    "N3_nost", "N3_pos_10", "N3_neg_10", "N3_act_10", "N3_deact_10", "N3_enjoy",
    "Q4",      "N4_pos_10", "N4_neg_10", "N4_act_10", "N4_deact_10", "N4_enjoy",
    # Control songs (4 sub-ratings each + outcome measures)
    "C1.1_nost", "C1.2_nost", "C1.3_nost", "C1.4_nost",
    "C1_pos_10", "C1_neg_10", "C1_act_10", "C1_deact_10", "C1_enjoy",
    "C2.1_nost", "C2.2_nost", "C2.3_nost", "C2.4_nost",
    "C2_pos_10", "C2_neg_10", "C2_act_10", "C2_deact_10", "C2_enjoy",
    "C3.1_nost", "C3.2_nost", "C3.3_nost", "C3.4_nost",
    "C3_pos_10", "C3_neg_10", "C3_act_10", "C3_deact_10", "C3_enjoy",
    "Q381", "Q396", "Q406", "Q413",
    "C4_pos_10", "C4_neg_10", "C4_act_10", "C4_deact_10", "C4_enjoy",
    # Metadata
    "FL_10_DO", "Duration (in seconds)",
    # SNS / BMRQ / SES
    *SNS_NUMERIC_COLS, SNS_FREQ_COL,
    *BMRQ_COLS,
    *SES_COUNTRY_COLS, *SES_COMMUNITY_COLS,
]

RENAME_MAP = {
    "ResponseId": "ID", "PROLIFIC_PID": "PROLIFIC_PID",
    "N1_nost": "N1_nost", "N1_pos_13": "N1_pos", "N1_neg_10": "N1_neg",
    "N1_act_10": "N1_act", "N1_deact_10": "N1_deact", "N1_enjoy": "N1_enjoy",
    "N2_nost": "N2_nost", "N2_pos_10": "N2_pos", "N2_neg_10": "N2_neg",
    "N2_act_10": "N2_act", "N2_deact_10": "N2_deact", "N2_enjoy": "N2_enjoy",
    "N3_nost": "N3_nost", "N3_pos_10": "N3_pos", "N3_neg_10": "N3_neg",
    "N3_act_10": "N3_act", "N3_deact_10": "N3_deact", "N3_enjoy": "N3_enjoy",
    "Q4":       "N4_nost", "N4_pos_10": "N4_pos", "N4_neg_10": "N4_neg",
    "N4_act_10": "N4_act", "N4_deact_10": "N4_deact", "N4_enjoy": "N4_enjoy",
    "C1.1_nost": "C1.1_nost", "C1.2_nost": "C1.2_nost",
    "C1.3_nost": "C1.3_nost", "C1.4_nost": "C1.4_nost",
    "C1_pos_10": "C1_pos", "C1_neg_10": "C1_neg",
    "C1_act_10": "C1_act", "C1_deact_10": "C1_deact", "C1_enjoy": "C1_enjoy",
    "C2.1_nost": "C2.1_nost", "C2.2_nost": "C2.2_nost",
    "C2.3_nost": "C2.3_nost", "C2.4_nost": "C2.4_nost",
    "C2_pos_10": "C2_pos", "C2_neg_10": "C2_neg",
    "C2_act_10": "C2_act", "C2_deact_10": "C2_deact", "C2_enjoy": "C2_enjoy",
    "C3.1_nost": "C3.1_nost", "C3.2_nost": "C3.2_nost",
    "C3.3_nost": "C3.3_nost", "C3.4_nost": "C3.4_nost",
    "C3_pos_10": "C3_pos", "C3_neg_10": "C3_neg",
    "C3_act_10": "C3_act", "C3_deact_10": "C3_deact", "C3_enjoy": "C3_enjoy",
    "Q381": "C4.1_nost", "Q396": "C4.2_nost",
    "Q406": "C4.3_nost", "Q413": "C4.4_nost",
    "C4_pos_10": "C4_pos", "C4_neg_10": "C4_neg",
    "C4_act_10": "C4_act", "C4_deact_10": "C4_deact", "C4_enjoy": "C4_enjoy",
    "FL_10_DO": "FL_10_DO",
    "Duration (in seconds)": "Duration",
    # SNS / BMRQ / SES columns are already named the way we want; identity
    # entries aren't strictly required for .rename() but are listed here for
    # clarity/completeness.
    **{c: c for c in SNS_NUMERIC_COLS},
    SNS_FREQ_COL: SNS_FREQ_COL,
    **{c: c for c in BMRQ_COLS},
    **{c: c for c in SES_COUNTRY_COLS},
    **{c: c for c in SES_COMMUNITY_COLS},
}

FL_DO_REPLACEMENTS = {
    "NostalgiaSong1": "Nost1", "NostalgiaSong2": "Nost2",
    "NostalgiaSong3": "Nost3", "NostalgiaSong4": "Nost4",
    "FL_22": "Cont1", "FL_20": "Cont2", "FL_21": "Cont3", "FL_182": "Cont4",
}

PROLIFIC_COLUMNS = [
    "Participant id", "Age", "Sex", "Ethnicity simplified",
    "Country of birth", "Country of residence", "Nationality",
    "Language", "Student status", "Employment status",
    "Place of most time spent before turning 18",
]


# ── Step 3: load Prolific demographic CSVs ───────────────────────────────────
def extract_numeric_value(val) -> float:
    if pd.isna(val):
        return np.nan
    match = re.search(r"(\d+)", str(val))
    return float(match.group(1)) if match else np.nan


print("\nLoading Prolific demographic CSVs...")
prolific_data: dict[str, pd.DataFrame] = {}

for country in COUNTRIES:
    path = PROLIFIC_DIR / f"{country} prolific.csv"
    if path.exists():
        df = pd.read_csv(path)
        df.columns = df.columns.str.strip()
        existing = [c for c in PROLIFIC_COLUMNS if c in df.columns]
        df_clean = df[existing].copy()
        if "Participant id" in df_clean.columns:
            df_clean = df_clean.rename(columns={"Participant id": "PROLIFIC_PID"})
        prolific_data[country] = df_clean
        print(f"  {country}: {len(df_clean)} records loaded from '{path.name}'")
    else:
        print(f"  Warning: '{path}' not found — demographics will be missing for {country}")
        prolific_data[country] = pd.DataFrame()


# ── SNS (Southampton Nostalgia Scale) ────────────────────────────────────────
# 7 items total, each conceptually on a 1-7 scale:
#   - Q472_1 .. Q472_6 are plain numeric ratings.
#   - Q478 ("Specifically, how often do you bring to mind nostalgic
#     experiences?") is collected as a text frequency response rather than a
#     numeric rating. This is the item that gets reverse coded; the mapping
#     below encodes the FINAL (post-reverse-code) 1-7 score directly, so no
#     further reversal is needed once this map is applied.
SNS_Q478_MAP = {
    "At least once a day": 7,
    "Three to four times a week": 6,
    "Approximately twice a week": 5,
    "Approximately once a week": 4,
    "Once or twice a month": 3,
    "Once every couple of months": 2,
    "Once or twice a year": 1,
}


def compute_sns_score(row):
    """Average of the 6 numeric SNS items + the reverse-coded Q478 item."""
    vals = []
    for col in SNS_NUMERIC_COLS:
        v = extract_numeric_value(row.get(col))
        if not pd.isna(v):
            vals.append(v)

    raw_freq = row.get(SNS_FREQ_COL)
    if pd.notna(raw_freq):
        mapped = SNS_Q478_MAP.get(str(raw_freq).strip())
        if mapped is not None:
            vals.append(mapped)

    if not vals:
        return np.nan
    return float(np.mean(vals))


# ── BMRQ (Barcelona Music Reward Questionnaire) ──────────────────────────────
# 20 items, 1-5 scale. Items 2 and 5 are reverse coded (reverse = 6 - x on a
# 1-5 scale). Final score is the SUM of all 20 items (not an average).
BMRQ_REVERSE_ITEMS = {2, 5}


def compute_bmrq_score(row):
    total = 0.0
    n_found = 0
    for i in range(1, 21):
        v = extract_numeric_value(row.get(f"BMRQ_{i}"))
        if pd.isna(v):
            continue
        if i in BMRQ_REVERSE_ITEMS:
            v = 6 - v
        total += v
        n_found += 1
    if n_found == 0:
        return np.nan
    return total


# ── SES (subjective socioeconomic status ladders) ────────────────────────────
# Each ladder is stored as 10 On/Off columns (one per rung). The rung the
# participant clicked is "On"; every other rung is "Off". The score is simply
# the rung number (1-10). If every rung is "Off" for a subject, that's a data
# issue worth flagging rather than silently coding as missing.
def compute_ses_score(row, cols, subject_id, ladder_name):
    for rung, col in enumerate(cols, start=1):
        val = row.get(col)
        if isinstance(val, str) and val.strip().lower() == "on":
            return rung, False
    print(f"  [FLAG] {ladder_name} ladder is all-OFF for subject {subject_id} — no rung selected")
    return np.nan, True


# ── Step 4: process each country's Qualtrics CSV ─────────────────────────────
all_data: list[pd.DataFrame] = []
stats = {
    "total_before_filter": 0,
    "processed_after_filter": 0,
    "prolific_merged": 0,
    "prolific_not_found": 0,
}

for country in COUNTRIES:
    qualtrics_path = QUALTRICS_DIR / f"{country}.csv"
    print(f"\nProcessing {qualtrics_path.name} ({country})...")

    if not qualtrics_path.exists():
        print(f"  ERROR: {qualtrics_path} not found — skipping.")
        continue

    try:
        df = pd.read_csv(qualtrics_path)
        # Qualtrics metadata rows at index 0 and 1 (after the real header row 0)
        df = df.drop([0, 1]).reset_index(drop=True)
        stats["total_before_filter"] += len(df)

        # Filter to subjects with processed .mat files
        df_filtered = df[df["ResponseId"].isin(processed_subjects)].copy()
        print(f"  Original: {len(df)} rows  →  After filter: {len(df_filtered)} subjects")

        if df_filtered.empty:
            print("  No matching subjects — skipping.")
            continue

        stats["processed_after_filter"] += len(df_filtered)

        # Strip the R_ prefix so IDs match the .mat file names
        df_filtered["ResponseId"] = df_filtered["ResponseId"].str.removeprefix("R_")

        # Select and rename columns
        existing_cols = [c for c in COLUMNS_TO_KEEP if c in df_filtered.columns]
        df_sub = df_filtered[existing_cols].rename(columns=RENAME_MAP).copy()

        # Apply FL_10_DO label replacements
        if "FL_10_DO" in df_sub.columns:
            for old, new in FL_DO_REPLACEMENTS.items():
                df_sub["FL_10_DO"] = df_sub["FL_10_DO"].str.replace(old, new, regex=False)

        # ── Simplify control trial nostalgia sub-ratings ──────────────────────
        # Each control song has up to 4 candidate tracks; we keep the first one
        # the participant rated as non-nostalgic (rating < 5).
        print("  Simplifying control trial nostalgia sub-ratings...")
        for cn in range(1, 5):
            sub_cols  = [f"C{cn}.{i}_nost" for i in range(1, 5)]
            data_cols = [f"C{cn}_{m}" for m in ("pos", "neg", "act", "deact", "enjoy")]

            existing_sub  = [c for c in sub_cols  if c in df_sub.columns]
            existing_data = [c for c in data_cols if c in df_sub.columns]

            if not (existing_sub and existing_data):
                continue

            new_nost_col = f"C{cn}_nost"

            def first_low_nostalgia(row, cols=existing_sub):
                for col in cols:
                    val = row.get(col)
                    if not pd.isna(val) and extract_numeric_value(val) < 5:
                        return val
                return np.nan

            df_sub[new_nost_col] = df_sub.apply(first_low_nostalgia, axis=1)

            # If no low-nostalgia track found, blank the outcome columns
            no_low = df_sub[new_nost_col].isna()
            for col in existing_data:
                df_sub.loc[no_low, col] = np.nan

            df_sub.drop(columns=existing_sub, inplace=True)

            has_nost  = df_sub[new_nost_col].notna().sum()
            has_data  = df_sub[existing_data[0]].notna().sum() if existing_data else 0
            print(f"    Control {cn}: {has_nost} with nost<5, {has_data} with trial data")

        # ── Compute SNS / BMRQ / SES scores ────────────────────────────────────
        print("  Computing SNS, BMRQ, and SES scores...")

        id_col = df_sub["ID"] if "ID" in df_sub.columns else pd.Series([None] * len(df_sub))

        if any(c in df_sub.columns for c in SNS_NUMERIC_COLS + [SNS_FREQ_COL]):
            df_sub["SNS_score"] = df_sub.apply(compute_sns_score, axis=1)
            n_sns = df_sub["SNS_score"].notna().sum()
            print(f"    SNS: {n_sns}/{len(df_sub)} subjects scored")
            df_sub.drop(columns=[c for c in SNS_NUMERIC_COLS + [SNS_FREQ_COL] if c in df_sub.columns],
                         inplace=True)

        if any(c in df_sub.columns for c in BMRQ_COLS):
            df_sub["BMRQ_score"] = df_sub.apply(compute_bmrq_score, axis=1)
            n_bmrq = df_sub["BMRQ_score"].notna().sum()
            print(f"    BMRQ: {n_bmrq}/{len(df_sub)} subjects scored")
            df_sub.drop(columns=[c for c in BMRQ_COLS if c in df_sub.columns], inplace=True)

        if any(c in df_sub.columns for c in SES_COUNTRY_COLS):
            ses_country = df_sub.apply(
                lambda row: compute_ses_score(row, SES_COUNTRY_COLS, id_col.loc[row.name], "SES country"),
                axis=1,
            )
            df_sub["SES_country_score"] = ses_country.apply(lambda x: x[0])
            df_sub["SES_country_flag"]  = ses_country.apply(lambda x: x[1])
            n_flagged_country = df_sub["SES_country_flag"].sum()
            print(f"    SES (country ladder): {n_flagged_country} flagged all-OFF")
            df_sub.drop(columns=[c for c in SES_COUNTRY_COLS if c in df_sub.columns], inplace=True)

        if any(c in df_sub.columns for c in SES_COMMUNITY_COLS):
            ses_community = df_sub.apply(
                lambda row: compute_ses_score(row, SES_COMMUNITY_COLS, id_col.loc[row.name], "SES community"),
                axis=1,
            )
            df_sub["SES_community_score"] = ses_community.apply(lambda x: x[0])
            df_sub["SES_community_flag"]  = ses_community.apply(lambda x: x[1])
            n_flagged_community = df_sub["SES_community_flag"].sum()
            print(f"    SES (community ladder): {n_flagged_community} flagged all-OFF")
            df_sub.drop(columns=[c for c in SES_COMMUNITY_COLS if c in df_sub.columns], inplace=True)

        df_sub["country"] = country

        # ── Merge Prolific demographics ───────────────────────────────────────
        if not prolific_data[country].empty and "PROLIFIC_PID" in df_sub.columns:
            df_sub["PROLIFIC_PID"] = df_sub["PROLIFIC_PID"].str.strip()
            prolific_data[country]["PROLIFIC_PID"] = (
                prolific_data[country]["PROLIFIC_PID"].astype(str).str.strip()
            )
            n_before = len(df_sub)
            df_sub = pd.merge(df_sub, prolific_data[country], on="PROLIFIC_PID", how="left")
            matched     = df_sub["Age"].notna().sum() if "Age" in df_sub.columns else 0
            not_matched = n_before - matched
            stats["prolific_merged"]     += matched
            stats["prolific_not_found"]  += not_matched
            print(f"  Prolific merge: {matched} matched, {not_matched} not found")
        else:
            print(f"  No Prolific data available for {country} — demographics skipped.")

        all_data.append(df_sub)

    except Exception as exc:
        import traceback
        print(f"  ERROR processing {country}: {exc}")
        traceback.print_exc()


# ── Step 5: combine, clean, reorder, and save ────────────────────────────────
if not all_data:
    print("\nERROR: No data was processed. Check paths and subject IDs.")
else:
    combined_df = pd.concat(all_data, ignore_index=True)

    # Strip label text from rating columns (e.g. "5 Somewhat Nostalgic" → "5")
    rating_cols = []
    for i in range(1, 5):
        rating_cols += [f"N{i}_{m}" for m in ("nost", "pos", "neg", "act", "deact", "enjoy")]
        rating_cols += [f"C{i}_{m}" for m in ("nost", "pos", "neg", "act", "deact", "enjoy")]
    cols_to_clean = [c for c in rating_cols if c in combined_df.columns]
    combined_df[cols_to_clean] = combined_df[cols_to_clean].replace(
        r"^(\d+)\s*[\s\S]*$", r"\1", regex=True
    )

    # Build final column order
    col_order = ["ID", "PROLIFIC_PID", "country", "Duration", "FL_10_DO"]
    for i in range(1, 5):
        col_order += [f"N{i}_{m}" for m in ("nost", "pos", "neg", "act", "deact", "enjoy")]
    for i in range(1, 5):
        col_order += [f"C{i}_{m}" for m in ("nost", "pos", "neg", "act", "deact", "enjoy")]
    col_order += [
        "SNS_score", "BMRQ_score",
        "SES_country_score", "SES_country_flag",
        "SES_community_score", "SES_community_flag",
    ]
    # Append any remaining columns (e.g. Prolific demographics) not yet listed
    col_order += [c for c in combined_df.columns if c not in col_order]

    combined_df = combined_df[[c for c in col_order if c in combined_df.columns]]
    combined_df.to_csv(OUTPUT_CSV, index=False)

    # ── Control trial summary ─────────────────────────────────────────────────
    print("\n" + "=" * 55)
    print("CONTROL TRIAL SUMMARY")
    print("=" * 55)
    for cn in range(1, 5):
        nc = f"C{cn}_nost"
        pc = f"C{cn}_pos"
        if nc in combined_df.columns:
            has_nost = combined_df[nc].notna().sum()
            has_data = combined_df[pc].notna().sum() if pc in combined_df.columns else "N/A"
            total    = len(combined_df)
            print(f"  Control {cn}: {has_nost}/{total} have nost<5,  {has_data}/{total} have trial data")

    # ── SNS / BMRQ / SES summary ───────────────────────────────────────────────
    print("\n" + "=" * 55)
    print("SNS / BMRQ / SES SUMMARY")
    print("=" * 55)
    if "SNS_score" in combined_df.columns:
        print(f"  SNS_score: {combined_df['SNS_score'].notna().sum()}/{len(combined_df)} scored, "
              f"mean={combined_df['SNS_score'].mean():.2f}")
    if "BMRQ_score" in combined_df.columns:
        print(f"  BMRQ_score: {combined_df['BMRQ_score'].notna().sum()}/{len(combined_df)} scored, "
              f"mean={combined_df['BMRQ_score'].mean():.2f}")
    if "SES_country_flag" in combined_df.columns:
        n_flag = combined_df["SES_country_flag"].sum()
        print(f"  SES_country_score: {combined_df['SES_country_score'].notna().sum()}/{len(combined_df)} scored, "
              f"{n_flag} flagged all-OFF")
    if "SES_community_flag" in combined_df.columns:
        n_flag = combined_df["SES_community_flag"].sum()
        print(f"  SES_community_score: {combined_df['SES_community_score'].notna().sum()}/{len(combined_df)} scored, "
              f"{n_flag} flagged all-OFF")

    print("\n" + "=" * 55)
    print("SUMMARY")
    print("=" * 55)
    print(f"  Subjects before filtering : {stats['total_before_filter']}")
    print(f"  Subjects after filtering  : {stats['processed_after_filter']}")
    print(f"  Unique subjects in output : {combined_df['ID'].nunique()}")
    print(f"  Prolific records merged   : {stats['prolific_merged']}")
    print(f"  Prolific records not found: {stats['prolific_not_found']}")
    print(f"\n  Output → {OUTPUT_CSV}")
    print(f"\n  Columns in output ({len(combined_df.columns)} total):")
    for i, col in enumerate(combined_df.columns, 1):
        print(f"    {i:2}. {col}")