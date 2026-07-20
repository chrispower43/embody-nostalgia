@echo off
REM ============================================================
REM Embody Nostalgia — Python environment bootstrap (Windows)
REM
REM Creates a project-local .venv and installs the pinned
REM dependencies in requirements.txt. Safe to re-run; it will
REM reuse an existing .venv rather than recreating it.
REM
REM Usage (run from anywhere, path-independent):
REM   setup\setup_env.bat
REM ============================================================
setlocal

set "SETUP_DIR=%~dp0"
for %%I in ("%SETUP_DIR%..") do set "PROJECT_ROOT=%%~fI\"
set "VENV_DIR=%PROJECT_ROOT%.venv"
set "REQUIREMENTS_FILE=%SETUP_DIR%requirements.txt"

REM MATLAB does not yet support the newest Python releases (e.g. 3.13+).
REM "py -3" picks whichever is newest on this machine, which can be too
REM new, so explicitly prefer known MATLAB-supported versions in order.
set "PY_LAUNCHER="
for %%V in (3.12 3.11 3.10 3.9) do (
    if not defined PY_LAUNCHER (
        py -%%V --version >nul 2>nul
        if not errorlevel 1 set "PY_LAUNCHER=py -%%V"
    )
)

if not defined PY_LAUNCHER (
    echo ERROR: Could not find Python 3.9-3.12 via the py launcher.
    echo Install one of these versions from python.org, then re-run this script.
    echo ^(MATLAB does not yet support newer releases such as 3.13/3.14.^)
    exit /b 1
)

echo Using base interpreter launcher: %PY_LAUNCHER%

if not exist "%VENV_DIR%" (
    echo Creating virtual environment at: %VENV_DIR%
    %PY_LAUNCHER% -m venv "%VENV_DIR%"
) else (
    echo Reusing existing virtual environment at: %VENV_DIR%
)

call "%VENV_DIR%\Scripts\python.exe" -m pip install --upgrade pip
call "%VENV_DIR%\Scripts\python.exe" -m pip install -r "%REQUIREMENTS_FILE%"

echo.
echo Done. Virtual environment ready at: %VENV_DIR%
echo MATLAB python executable path:
echo   %VENV_DIR%\Scripts\python.exe

endlocal
