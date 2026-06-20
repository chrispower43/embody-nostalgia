"""
generate_removal_lists.py
─────────────────────────
Generates two CSV files listing subjects to remove so that each country
reaches the target sample size:
  - preprocessing_remove_paired.csv     (from the paired/preprocessed pipeline)
  - preprocessing_remove_unfiltered.csv (from the all/unfiltered pipeline)

Removal priority: most-recently-collected subjects are removed first.

Expected folder layout (relative to this script / the MATLAB project root):
  qualtrics_data/
      BR.csv  IN.csv  JP.csv  SP.csv  US.csv
  final&new_subjects/
      subject_list_preprocessed.csv
      subject_list_unfiltered.csv

Outputs are written to:
  final&new_subjects/preprocessing_remove_paired.csv
  final&new_subjects/preprocessing_remove_unfiltered.csv

Usage from MATLAB:
  pyrunfile("generate_removal_lists.py")
  % or, to override targets:
  pyrunfile("generate_removal_lists.py", TARGET_PAIRED=int32(55), TARGET_ALL=int32(65))
"""

import os, sys
import pandas as pd
from pathlib import Path

print("DEBUG (python): EMBODY_PROJECT_ROOT =", os.environ.get("EMBODY_PROJECT_ROOT", "NOT SET"))

_project_root = os.environ.get("EMBODY_PROJECT_ROOT")
if _project_root:
    PROJECT_ROOT = Path(_project_root)
else:
    PROJECT_ROOT = Path(__file__).parent.parent  # python_scripts/ -> project root

sys.path.insert(0, str(PROJECT_ROOT / "config"))
from config_loader import load_config

cfg = load_config(PROJECT_ROOT / "config" / "config.toml")  # explicit path, no __file__

COUNTRIES      = cfg.countries
TARGET_PAIRED  = cfg.target_paired
TARGET_ALL     = cfg.target_all

PROJECT_ROOT          = cfg.subjects_dir.parent
QUALTRICS_DIR         = cfg.qualtrics_data
SUBJECTS_DIR          = cfg.subjects_dir
SUBJECT_LIST_PAIRED   = SUBJECTS_DIR / "subject_list_preprocessed.csv"
SUBJECT_LIST_ALL      = SUBJECTS_DIR / "subject_list_unfiltered.csv"
OUTPUT_PAIRED_CSV     = SUBJECTS_DIR / "preprocessing_remove_paired.csv"
OUTPUT_ALL_CSV        = SUBJECTS_DIR / "preprocessing_remove_unfiltered.csv"


# ── Load recency info from Qualtrics country CSVs ────────────────────────────
# Qualtrics CSVs have 3 header rows; row 0 = real headers, rows 1–2 = metadata.
def load_country_csv(country: str) -> pd.DataFrame:
    path = QUALTRICS_DIR / f"{country}.csv"
    df = pd.read_csv(path, skiprows=[1, 2])
    # Strip R_ prefix to match subject list IDs
    df["subject"] = df["ResponseId"].str.removeprefix("R_")
    df["EndDate"] = pd.to_datetime(df["EndDate"])
    return df[["subject", "EndDate"]].dropna()


print("Loading Qualtrics CSVs for recency information...")
recency = pd.concat([load_country_csv(c) for c in COUNTRIES], ignore_index=True)
recency = recency.drop_duplicates("subject")
print(f"  Loaded {len(recency)} unique subject end-dates.\n")


# ── Helper: compute subjects to remove ───────────────────────────────────────
def get_subjects_to_remove(
    subject_csv: Path,
    target_per_country: int,
    label: str,
) -> list[tuple[str, str]]:

    df = pd.read_csv(subject_csv)
    df = df[df["country"].isin(COUNTRIES)].copy()

    # Join with recency — subjects missing from Qualtrics CSVs get NaT
    df = df.merge(recency, on="subject", how="left")

    missing_dates = df["EndDate"].isna().sum()
    if missing_dates:
        print(
            f"  Warning: {missing_dates} subject(s) in {subject_csv.name} "
            "had no matching EndDate — they will be treated as most recent."
        )

    to_remove_all: list[tuple[str, str]] = []

    print(f"{'─'*55}")
    print(f"  {label}  (target: {target_per_country} per country)")
    print(f"{'─'*55}")
    print(f"  {'Country':<10} {'Current':>8} {'Target':>8} {'Remove':>8}")
    print(f"  {'─'*40}")

    for country in COUNTRIES:
        group = df[df["country"] == country].copy()
        n_current = len(group)
        n_remove  = max(0, n_current - target_per_country)

        # Sort descending by EndDate; NaT (unknown date) treated as most recent.
        group = group.sort_values("EndDate", ascending=False, na_position="first")
        to_remove = group.head(n_remove)["subject"].tolist()
        to_remove_all.extend([(s, country) for s in to_remove])

        print(f"  {country:<10} {n_current:>8} {target_per_country:>8} {n_remove:>8}")

    print(f"  {'─'*40}")
    total_remove  = len(to_remove_all)
    total_current = len(df)
    print(
        f"  {'TOTAL':<10} {total_current:>8} "
        f"{target_per_country * len(COUNTRIES):>8} {total_remove:>8}"
    )

    return to_remove_all


# ── Run for both pipelines ────────────────────────────────────────────────────
remove_paired = get_subjects_to_remove(SUBJECT_LIST_PAIRED, TARGET_PAIRED, "preprocessed (paired)")
print()
remove_all    = get_subjects_to_remove(SUBJECT_LIST_ALL,    TARGET_ALL,    "all_preprocessed")


# ── Save lists to CSV files ───────────────────────────────────────────────────
def save_removal_csv(to_remove: list[tuple[str, str]], path: Path) -> None:
    remove_df = pd.DataFrame(to_remove, columns=["subject", "country"])
    remove_df.to_csv(path, index=False)
    print(f"  Saved → {path}")


print("\nSaving removal lists...")
save_removal_csv(remove_paired, OUTPUT_PAIRED_CSV)
save_removal_csv(remove_all,    OUTPUT_ALL_CSV)


# ── Print human-readable summary ──────────────────────────────────────────────
def print_removal_list(to_remove: list[tuple[str, str]], label: str) -> None:
    print(f"\n{'═'*55}")
    print(f"  Subjects to REMOVE from {label}")
    print(f"{'═'*55}")
    by_country: dict[str, list[str]] = {}
    for subj, country in to_remove:
        by_country.setdefault(country, []).append(subj)
    for country in COUNTRIES:
        subjects = by_country.get(country, [])
        if subjects:
            print(f"\n  [{country}] ({len(subjects)} subjects)")
            for s in subjects:
                print(f"    {s}")
    if not to_remove:
        print("  None — already at or below target.")


print_removal_list(remove_paired, "preprocessed/")
print_removal_list(remove_all,    "all_preprocessed/")

print(f"\n{'═'*55}")
print("  Note: all_preprocessed removals are determined solely")
print("  by recency, independent of paired pipeline inclusion.")
print(f"{'═'*55}\n")
