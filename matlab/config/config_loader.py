"""
config_loader.py
────────────────
Shared helper imported by both Python scripts.
Reads config.toml and exposes a simple ProjectConfig dataclass.

Usage:
    from config_loader import load_config
    cfg = load_config()          # finds config.toml next to this file
    print(cfg.subjects_dir)
"""

from __future__ import annotations
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# tomllib is stdlib in Python 3.11+; fall back to the tomli backport
if sys.version_info >= (3, 11):
    import tomllib
else:
    try:
        import tomli as tomllib          # pip install tomli
    except ImportError:
        raise ImportError(
            "Python < 3.11 requires the 'tomli' package: pip install tomli"
        )


@dataclass
class ProjectConfig:
    # Paths
    subjects_dir:    Path
    qualtrics_data:  Path
    prolific_data:   Path
    combined_csv:    Path
    regression_csv:  Path

    # Countries
    countries:      list[str]
    countries_all:  list[str]

    # Pruning
    target_paired:  int
    target_all:     int

    # Pictures
    pic_prefix:     str
    pic_pq0:        Path
    pic_pq1and3:    Path
    pic_regression: Path

    # Raw TOML (for anything not explicitly mapped above)
    _raw: dict = field(default_factory=dict, repr=False)


_CANONICAL = "final&new_subjects"


def _derive_prefix(subjects_dir: str) -> str:
    """Mirror the MATLAB derive_prefix() logic."""
    if subjects_dir == _CANONICAL:
        return ""
    remainder = subjects_dir.replace(_CANONICAL, "").strip()
    remainder = re.sub(r"^[-–—\s]+", "", remainder)   # strip leading dashes
    remainder = remainder.replace(" ", "_")
    if remainder and not remainder.endswith("_"):
        remainder += "_"
    return remainder


def load_config(config_path: Path | str | None = None) -> ProjectConfig:
    """
    Parse config.toml and return a ProjectConfig.

    config_path defaults to config.toml in the same directory as this file.
    """
    if config_path is None:
        config_path = Path(__file__).parent / "config.toml"
    config_path = Path(config_path)

    if not config_path.exists():
        raise FileNotFoundError(
            f"Config file not found: {config_path}\n"
            "Expected config.toml next to the Python scripts."
        )

    with open(config_path, "rb") as f:
        raw = tomllib.load(f)

    root = Path(config_path).parent.parent    # project root (same dir as config.toml)

    # Paths
    p            = raw.get("paths", {})
    subjects_dir = p.get("subjects_dir", _CANONICAL)
    qualtrics    = p.get("qualtrics_data", "qualtrics_data")
    prolific     = p.get("prolific_data",  "prolific_data")
    combined_csv = p.get("combined_csv",   "combined_data_all.csv")
    regression_csv = p.get("regression_csv", "regression_all.csv")

    # Countries
    c            = raw.get("countries", {})
    countries    = c.get("list",         ["BR", "IN", "US", "SP", "JP"])
    countries_all = c.get("with_aggregate", countries + ["all"])

    # Pruning
    pr = raw.get("pruning", {})
    target_paired = int(pr.get("target_paired", 60))
    target_all    = int(pr.get("target_all",    70))

    # Picture prefix
    pics          = raw.get("pictures", {})
    override      = pics.get("prefix_override", "").strip()
    pic_prefix    = override if override else _derive_prefix(subjects_dir)

    subs = pics.get("subfolders", {})
    base_pq0        = subs.get("pq0",        "PQ0")
    base_pq1and3    = subs.get("pq1and3",    "PQ1&3")
    base_regression = subs.get("regression", "regression")

    def pic_path(subfolder: str) -> Path:
        name = f"{pic_prefix}{subfolder}" if pic_prefix else subfolder
        return root / "pictures" / name

    return ProjectConfig(
        subjects_dir    = root / subjects_dir,
        qualtrics_data  = root / qualtrics,
        prolific_data   = root / prolific,
        combined_csv    = root / combined_csv,
        regression_csv  = root / regression_csv,
        countries       = countries,
        countries_all   = countries_all,
        target_paired   = target_paired,
        target_all      = target_all,
        pic_prefix      = pic_prefix,
        pic_pq0         = pic_path(base_pq0),
        pic_pq1and3     = pic_path(base_pq1and3),
        pic_regression  = pic_path(base_regression),
        _raw            = raw,
    )
