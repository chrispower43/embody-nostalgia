#!/usr/bin/env bash
# ============================================================
# Embody Nostalgia — Python environment bootstrap (macOS/Linux)
#
# Creates a project-local .venv and installs the pinned
# dependencies in requirements.txt. Safe to re-run; it will
# reuse an existing .venv rather than recreating it.
#
# Usage (run from anywhere, path-independent):
#   bash setup/setup_env.sh
# ============================================================
set -euo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SETUP_DIR/.." && pwd)"
VENV_DIR="$PROJECT_ROOT/.venv"
REQUIREMENTS_FILE="$SETUP_DIR/requirements.txt"

# MATLAB does not yet support the newest Python releases (e.g. 3.13+),
# so explicitly prefer known MATLAB-supported versions in order, rather
# than a bare "python3" which may resolve to whatever is newest.
PYTHON_BIN="$(command -v python3.12 || command -v python3.11 || command -v python3.10 || command -v python3.9 || true)"

if [ -z "$PYTHON_BIN" ]; then
    echo "ERROR: Could not find Python 3.9-3.12 on PATH." >&2
    echo "Install one of these versions, then re-run this script." >&2
    echo "(MATLAB does not yet support newer releases such as 3.13/3.14.)" >&2
    exit 1
fi

echo "Using base interpreter: $PYTHON_BIN ($($PYTHON_BIN --version 2>&1))"

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment at: $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
else
    echo "Reusing existing virtual environment at: $VENV_DIR"
fi

"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install -r "$REQUIREMENTS_FILE"

echo ""
echo "Done. Virtual environment ready at: $VENV_DIR"
echo "MATLAB python executable path:"
echo "  $VENV_DIR/bin/python"
