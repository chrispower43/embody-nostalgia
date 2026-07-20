function setup_python_env()
%SETUP_PYTHON_ENV  One-time-per-session Python environment bootstrap.
%
%   Run this once, right after opening MATLAB (and again any time you
%   pull new code or see a Python-related error) - BEFORE running
%   preprocessing.m or any other script that touches py.*.
%
%   What it does:
%     1. Creates a project-local .venv if one doesn't exist yet
%        (by shelling out to setup/setup_env.sh or setup/setup_env.bat).
%     2. Points MATLAB's pyenv at that venv's python executable.
%     3. Verifies numpy / pandas / tomli import correctly.
%
%   This intentionally does NOT run automatically inside
%   preprocessing.m, because pyenv('Version', ...) can only be set
%   once per MATLAB session (before any py.* call has executed).
%   Since preprocessing.m may be run multiple times per session,
%   the environment setup is split out here so it only runs once.
%
%   Usage:
%       >> setup_python_env
%       >> preprocessing
%       >> preprocessing     % can re-run freely, no need to call this again
%
%   If you see an error like:
%       "Error setting default Python for MATLAB ... previously set"
%   it means py.* was already touched this session with a different
%   interpreter. Restart MATLAB, then run setup_python_env first,
%   before anything else.

    project_root = fileparts(mfilename('fullpath'));

    fprintf('=== Embody Nostalgia: Python environment setup ===\n');
    fprintf('Project root: %s\n', project_root);

    % ---- 1. Locate (or create) the project .venv -----------------------
    if ispc
        venv_python = fullfile(project_root, '.venv', 'Scripts', 'python.exe');
        bootstrap_cmd = sprintf('"%s"', fullfile(project_root, 'setup', 'setup_env.bat'));
    else
        venv_python = fullfile(project_root, '.venv', 'bin', 'python');
        bootstrap_cmd = sprintf('bash "%s"', fullfile(project_root, 'setup', 'setup_env.sh'));
    end

    % ---- 1. Create the venv (if needed) and sync installed packages ----
    % The bootstrap script itself skips venv creation if .venv already
    % exists, but always re-runs "pip install -r requirements.txt" - this
    % is what picks up new/changed dependencies after a `git pull`, so we
    % always invoke it rather than only on first setup.
    if isfile(venv_python)
        fprintf('Found existing virtual environment:\n  %s\n', venv_python);
        fprintf('Syncing installed packages with setup/requirements.txt...\n');
    else
        fprintf('No virtual environment found. Creating one now...\n');
    end
    fprintf('  (running: %s)\n', bootstrap_cmd);

    old_dir = cd(project_root);
    cleanup_obj = onCleanup(@() cd(old_dir)); %#ok<NASGU>
    [status, output] = system(bootstrap_cmd);
    fprintf('%s\n', output);

    if status ~= 0
        error('setup_python_env:bootstrapFailed', ...
            'Failed to create/update the virtual environment. See output above.');
    end

    assert(isfile(venv_python), ...
        'setup_python_env:missingInterpreter', ...
        'Expected a venv python executable at:\n  %s\nbut it was not found after setup.', ...
        venv_python);

    % ---- 2. Point MATLAB's pyenv at the venv ----------------------------
    current_env = pyenv;

    if strcmp(current_env.Status, 'Loaded') && ~strcmpi(current_env.Executable, venv_python)
        error('setup_python_env:alreadyLoaded', ...
            ['MATLAB has already loaded a different Python interpreter this session:\n' ...
             '  %s\n' ...
             'pyenv can only be changed before Python has been used.\n' ...
             'Restart MATLAB, then run setup_python_env() as the very first command.'], ...
            current_env.Executable);
    end

    if ~strcmpi(current_env.Executable, venv_python)
        try
            pyenv('Version', venv_python);
        catch ME
            if contains(ME.message, 'not supported')
                error('setup_python_env:unsupportedPythonVersion', ...
                    ['The virtual environment at:\n  %s\n' ...
                     'was built with a Python version MATLAB does not support.\n\n' ...
                     'Fix: delete the .venv folder, then re-run setup_python_env ' ...
                     '(setup/setup_env.sh and setup/setup_env.bat now prefer ' ...
                     'Python 3.9-3.12 automatically). If none of those versions ' ...
                     'are installed on this machine, install one from python.org ' ...
                     'first.\n\nUnderlying error: %s'], ...
                    venv_python, ME.message);
            end
            error('setup_python_env:pyenvFailed', ...
                ['Could not set pyenv to the project venv:\n  %s\n\n' ...
                 'Underlying error: %s\n\n' ...
                 'If this says Python was already initialized, restart MATLAB and run\n' ...
                 'setup_python_env() before any other command.'], ...
                venv_python, ME.message);
        end
    end

    env_info = pyenv;
    fprintf('MATLAB pyenv now points to:\n');
    fprintf('  Executable: %s\n', env_info.Executable);
    fprintf('  Version:    %s\n', env_info.Version);

    % ---- 3. Verify required packages import correctly --------------------
    fprintf('\nVerifying required packages...\n');
    try
        np = py.importlib.import_module('numpy');
        pd = py.importlib.import_module('pandas');
        sp = py.importlib.import_module('scipy');
        % Use py.getattr (not dot-notation) for dunder attributes: MATLAB's
        % parser requires field names to start with a letter, so
        % np.__version__ fails to parse even though it's valid Python.
        fprintf('  numpy  %s\n', string(py.getattr(np, '__version__')));
        fprintf('  pandas %s\n', string(py.getattr(pd, '__version__')));
        fprintf('  scipy  %s\n', string(py.getattr(sp, '__version__')));
    catch ME
        error('setup_python_env:importFailed', ...
            ['numpy/pandas/scipy failed to import from the project venv.\n' ...
             'Try re-running the bootstrap script directly:\n  %s\n\n' ...
             'Underlying error: %s'], bootstrap_cmd, ME.message);
    end

    py_version = double(env_info.Version);
    if py_version < 3.11
        try
            tomli_mod = py.importlib.import_module('tomli');
            fprintf('  tomli  %s\n', string(py.getattr(tomli_mod, '__version__')));
        catch ME
            error('setup_python_env:importFailed', ...
                ['tomli failed to import (required for Python < 3.11).\n' ...
                 'Underlying error: %s'], ME.message);
        end
    else
        fprintf('  tomli  not required (Python %s has stdlib tomllib)\n', env_info.Version);
    end

    fprintf('\n=== Environment ready. You can now run preprocessing.m ===\n');
end