"""
analyse_ratings.py
──────────────────
Computes per-measure means and paired t-tests (nostalgia vs. familiar control)
for subjects included in subject_list_preprocessed.csv.

Trial pairing semantics
────────────────────────
A nostalgia trial i (Ni_*) is only included if its matching control trial i
(Ci_*) also exists for that subject (i.e. i is in that subject's valid_pairs,
mirroring the pairing already enforced in preprocessing.m / the
*_preprocessed.mat files). Unmatched trials (a Nost with no Cont, or vice
versa) are excluded entirely rather than folded into the subject's average.
This keeps analyse_ratings.py consistent with pixel_regression_subjectlevel.m
and pca_regression_subjectlevel.m, which also only use matched pairs.

Pair validity is determined once per subject (using the 'nost' rating column
as the indicator of whether a trial was administered) and then applied
uniformly across all six measures, since a trial's pairing is a property of
the trial itself, not of any one measure.

Measures per trial:
    nost   – nostalgic rating
    pos    – positive valence
    neg    – negative valence
    act    – activation
    deact  – deactivation
    enjoy  – enjoyment

Usage:
    python analyse_ratings.py                  # from project root
    python python_scripts/analyse_ratings.py   # or via MATLAB pyrunfile()
"""

import os
import sys
import numpy as np
import pandas as pd
from pathlib import Path
from scipy import stats

# ── Locate project root & load config ─────────────────────────────────────────
# NOTE: __file__ is unavailable when this script is invoked via MATLAB's
# pyrunfile(), so there is no safe fallback to derive PROJECT_ROOT from the
# script's own location. The caller MUST set EMBODY_PROJECT_ROOT explicitly.
# From MATLAB, remember that plain setenv() does NOT propagate to the
# embedded Python interpreter — set it via:
#   py.os.environ().update(py.dict(pyargs('EMBODY_PROJECT_ROOT', project_root)))
_project_root = os.environ.get("EMBODY_PROJECT_ROOT")
if not _project_root:
    raise RuntimeError(
        "EMBODY_PROJECT_ROOT is not set. This script cannot infer its own "
        "location when run via pyrunfile(), so the caller must set this "
        "environment variable explicitly before invoking analyse_ratings.py.\n"
        "From MATLAB, set it via:\n"
        "  py.os.environ().update(py.dict(pyargs('EMBODY_PROJECT_ROOT', project_root)))"
    )
PROJECT_ROOT = Path(_project_root)

print(f"[DEBUG] PROJECT_ROOT = {PROJECT_ROOT}")

sys.path.insert(0, str(PROJECT_ROOT / "config"))
from config_loader import load_config

cfg = load_config(PROJECT_ROOT / "config" / "config.toml")

SUBJECTS_DIR  = cfg.subjects_dir
COMBINED_CSV  = cfg.combined_csv

SUBJECT_LIST  = SUBJECTS_DIR / "subject_list_preprocessed.csv"

print(f"[DEBUG] SUBJECTS_DIR  = {SUBJECTS_DIR}")
print(f"[DEBUG] COMBINED_CSV  = {COMBINED_CSV}")
print(f"[DEBUG] SUBJECT_LIST  = {SUBJECT_LIST}")

# ── Measures to analyse ────────────────────────────────────────────────────────
MEASURES = ["nost", "pos", "neg", "act", "deact", "enjoy"]
TRIAL_INDICES = [1, 2, 3, 4]

# ── Load subject list ──────────────────────────────────────────────────────────
print(f"\nLoading subject list: {SUBJECT_LIST}")
subj_df = pd.read_csv(SUBJECT_LIST)
included_subjects = set(subj_df["subject"].astype(str).str.strip())
print(f"  {len(included_subjects)} preprocessed subjects listed.")
print(f"[DEBUG] Countries in subject list: {sorted(subj_df['country'].unique())}")
print(f"[DEBUG] Subjects per country:\n{subj_df['country'].value_counts().to_string()}")

# ── Load combined data ─────────────────────────────────────────────────────────
print(f"\nLoading combined data: {COMBINED_CSV}")
df_raw = pd.read_csv(COMBINED_CSV, dtype=str)
print(f"[DEBUG] combined_data_all.csv shape (raw): {df_raw.shape}")
print(f"[DEBUG] Columns: {list(df_raw.columns)}")

df = df_raw.copy()
df["ID"] = df["ID"].astype(str).str.strip()

# Filter to only preprocessed subjects
df_all = df.copy()
df = df[df["ID"].isin(included_subjects)].copy()
n_dropped = len(df_all) - len(df)
print(f"\n  Rows in combined CSV           : {len(df_all)}")
print(f"  Rows matching preprocessed list: {len(df)}")
print(f"  Rows dropped (not in list)     : {n_dropped}")

# IDs in subject list but missing from combined CSV
csv_ids = set(df_all["ID"])
missing_from_csv = included_subjects - csv_ids

if missing_from_csv:
    print(f"[DEBUG] {len(missing_from_csv)} subject(s) in preprocessed list but NOT found in combined CSV.")

    # --- Check 1: R_ prefix mismatch ---
    missing_with_prefix    = [s for s in missing_from_csv if ("R_" + s) in csv_ids]
    missing_without_prefix = [s for s in missing_from_csv if s.startswith("R_") and s[2:] in csv_ids]
    if missing_with_prefix:
        print(f"[DEBUG] ID PREFIX MISMATCH: {len(missing_with_prefix)} subject(s) found in CSV only when 'R_' is prepended.")
        print(f"         e.g. subject list has '{missing_with_prefix[0]}' but CSV has 'R_{missing_with_prefix[0]}'")
    if missing_without_prefix:
        print(f"[DEBUG] ID PREFIX MISMATCH: {len(missing_without_prefix)} subject(s) found in CSV only when 'R_' is stripped.")
        print(f"         e.g. subject list has '{missing_without_prefix[0]}' but CSV has '{missing_without_prefix[0][2:]}'")

    # --- Check 2: case-insensitive match ---
    csv_ids_lower       = {s.lower(): s for s in csv_ids}
    missing_case        = [s for s in missing_from_csv if s.lower() in csv_ids_lower]
    if missing_case:
        print(f"[DEBUG] CASE MISMATCH: {len(missing_case)} subject(s) match CSV IDs only case-insensitively.")
        for s in missing_case[:5]:
            print(f"         subject list: '{s}'  ->  CSV: '{csv_ids_lower[s.lower()]}'")

    # --- Check 3: whitespace / hidden characters ---
    csv_ids_stripped = {s.strip(): s for s in csv_ids}
    missing_ws       = [s for s in missing_from_csv if s.strip() in csv_ids_stripped and s not in csv_ids]
    if missing_ws:
        print(f"[DEBUG] WHITESPACE MISMATCH: {len(missing_ws)} subject(s) match after stripping whitespace.")

    # --- Check 4: show raw repr of a few mismatched IDs on both sides ---
    print(f"\n[DEBUG] Sample missing IDs (repr from subject list):")
    for s in sorted(missing_from_csv)[:5]:
        print(f"         {repr(s)}")
    print(f"[DEBUG] Sample IDs from combined CSV (repr):")
    for s in sorted(csv_ids)[:5]:
        print(f"         {repr(s)}")
else:
    print(f"[DEBUG] All preprocessed subjects found in combined CSV.")

# Convert all rating columns to numeric
rating_cols = [f"{cond}{i}_{m}"
               for cond in ("N", "C")
               for i in range(1, 5)
               for m in MEASURES]
present_rating_cols = [c for c in rating_cols if c in df.columns]
missing_rating_cols = [c for c in rating_cols if c not in df.columns]
print(f"\n[DEBUG] Rating columns present : {len(present_rating_cols)}")
if missing_rating_cols:
    print(f"[DEBUG] Rating columns missing : {missing_rating_cols}")

for col in present_rating_cols:
    df[col] = pd.to_numeric(df[col], errors="coerce")

# ── Determine matched-pair trial indices per subject ───────────────────────────
# A trial index i counts as a "valid pair" for a subject only if BOTH
# Ni_nost and Ci_nost are present (non-NaN). This mirrors the valid_pairs
# field already computed during preprocessing (preprocessing.m /
# *_preprocessed.mat) and is used consistently across all six measures,
# since pairing is a property of the trial, not of any individual measure.
print("\n[DEBUG] Determining matched-pair trial indices per subject (using 'nost' as trial-presence indicator)...")

pair_mask = {}   # trial index -> boolean Series over df.index
for i in TRIAL_INDICES:
    n_col = f"N{i}_nost"
    c_col = f"C{i}_nost"
    if n_col in df.columns and c_col in df.columns:
        pair_mask[i] = df[n_col].notna() & df[c_col].notna()
    else:
        pair_mask[i] = pd.Series(False, index=df.index)

n_valid_pairs_per_subject = sum(pair_mask[i].astype(int) for i in TRIAL_INDICES)
print(f"[DEBUG] Distribution of # valid pairs per subject:\n"
      f"{n_valid_pairs_per_subject.value_counts().sort_index().to_string()}")

n_zero_pair_subjects = int((n_valid_pairs_per_subject == 0).sum())
if n_zero_pair_subjects:
    print(f"[DEBUG] WARNING: {n_zero_pair_subjects} subject(s) in the preprocessed list have "
          f"ZERO matched nostalgia/control pairs and will be excluded from every measure.")

# ── Build per-subject, per-measure averages, restricted to matched pairs ──────
print("\n[DEBUG] Non-NaN counts per trial column (after numeric conversion):")
for m in MEASURES:
    nost_cols = [f"N{i}_{m}" for i in TRIAL_INDICES if f"N{i}_{m}" in df.columns]
    cont_cols = [f"C{i}_{m}" for i in TRIAL_INDICES if f"C{i}_{m}" in df.columns]
    nost_counts = {c: int(df[c].notna().sum()) for c in nost_cols}
    cont_counts = {c: int(df[c].notna().sum()) for c in cont_cols}
    print(f"  {m:<8}  nost: {nost_counts}  cont: {cont_counts}")

    # Mask each trial's Ni_{m} / Ci_{m} value to NaN unless that trial index
    # is a matched pair for this subject, then average only across matched
    # trials. This is the key change from the previous version, which
    # averaged across all available trials regardless of pairing.
    nost_masked = pd.DataFrame({
        f"N{i}_{m}": df[f"N{i}_{m}"].where(pair_mask[i])
        for i in TRIAL_INDICES if f"N{i}_{m}" in df.columns
    })
    cont_masked = pd.DataFrame({
        f"C{i}_{m}": df[f"C{i}_{m}"].where(pair_mask[i])
        for i in TRIAL_INDICES if f"C{i}_{m}" in df.columns
    })

    df[f"nost_avg_{m}"] = nost_masked.mean(axis=1, skipna=True)
    df[f"cont_avg_{m}"] = cont_masked.mean(axis=1, skipna=True)

df["n_valid_pairs"] = n_valid_pairs_per_subject

# ── Paired t-test per measure ──────────────────────────────────────────────────
print("\n" + "=" * 75)
print(f"  {'Measure':<10} {'n pairs':>8} {'Nost Mean':>10} {'Cont Mean':>10} "
      f"{'t':>8} {'df':>6} {'p':>10}")
print("=" * 75)

results = []
for m in MEASURES:
    # Keep only subjects with at least one matched trial pair contributing
    # to both nost_avg_{m} and cont_avg_{m}. Subjects with zero valid pairs
    # (n_valid_pairs == 0) will naturally have NaN here and drop out.
    paired = df[[f"nost_avg_{m}", f"cont_avg_{m}"]].dropna()
    n_pairs = len(paired)

    n_nost_only = df[f"nost_avg_{m}"].notna().sum() - n_pairs
    n_cont_only = df[f"cont_avg_{m}"].notna().sum() - n_pairs

    if n_pairs < 2:
        print(f"  {m:<10} — insufficient paired data (n={n_pairs}), skipping.")
        continue

    nost_mean = paired[f"nost_avg_{m}"].mean()
    nost_sd   = paired[f"nost_avg_{m}"].std(ddof=1)
    cont_mean = paired[f"cont_avg_{m}"].mean()
    cont_sd   = paired[f"cont_avg_{m}"].std(ddof=1)

    t_stat, p_val = stats.ttest_rel(
        paired[f"nost_avg_{m}"],
        paired[f"cont_avg_{m}"]
    )
    dof = n_pairs - 1

    print(f"  {m:<10} {n_pairs:>8} {nost_mean:>10.3f} {cont_mean:>10.3f} "
          f"{t_stat:>8.3f} {dof:>6d} {p_val:>10.4f}")

    results.append({
        "measure": m,
        "n_pairs": n_pairs,
        "nost_mean": nost_mean,
        "nost_sd": nost_sd,
        "cont_mean": cont_mean,
        "cont_sd": cont_sd,
        "t": t_stat,
        "df": dof,
        "p": p_val,
    })

print("=" * 75)

results_df = pd.DataFrame(results)
out_path = PROJECT_ROOT / "rating_stats_results.csv"
results_df.to_csv(out_path, index=False)
print(f"\nResults written to {out_path}")
print("\nDone.")