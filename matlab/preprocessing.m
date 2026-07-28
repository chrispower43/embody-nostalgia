%% Combined emBODY preprocessing script
%  Runs two pipelines in one pass per subject:
%    - Paired trials only  -> <region>/preprocessed/
%    - All trials          -> <region>/unfiltered/
close all
clear

cfg      = read_config();
countries = cfg.countries_all;
subjects  = [cfg.subjects_dir '/'];

%% === Verify Python environment ===
% setup_python_env() is responsible for binding MATLAB's pyenv to the
% project's .venv (this can only be done once per MATLAB session, before
% any py.* call, which is why it isn't done here — preprocessing.m may
% be run multiple times in one session). This block just checks that it
% was actually run, and sets up the path/env bits that are safe to redo
% on every call.
project_root = fileparts(mfilename('fullpath'));

if ispc
    expected_python = fullfile(project_root, '.venv', 'Scripts', 'python.exe');
else
    expected_python = fullfile(project_root, '.venv', 'bin', 'python');
end

current_env = pyenv;
if ~strcmpi(current_env.Executable, expected_python)
    error('preprocessing:pythonEnvNotSet', ...
        ['MATLAB is not using the project virtual environment.\n' ...
         'Run setup_python_env() once at the start of this MATLAB session, ' ...
         'then re-run preprocessing.\n  Expected: %s\n  Actual:   %s'], ...
        expected_python, current_env.Executable);
end
fprintf('Using Python: %s (%s)\n', current_env.Executable, current_env.Version);

% Pass project root to Python scripts via environment variable.
% NOTE: MATLAB's setenv() does not reliably propagate to the embedded
% Python interpreter's os.environ (confirmed on this setup), so we set
% it directly through Python as well.
setenv('EMBODY_PROJECT_ROOT', project_root);   % harmless to keep, in case other tools check it
py.os.environ().update(py.dict(pyargs('EMBODY_PROJECT_ROOT', project_root)));

% Add config folder to Python path so config_loader.py can be found
config_dir = fullfile(project_root, 'config');
if count(py.sys.path, config_dir) == 0
    py.sys.path().insert(int32(0), config_dir);
end
% Add python_scripts folder too (if scripts live there)
py_dir = fullfile(project_root, 'python_scripts');
if count(py.sys.path, py_dir) == 0
    py.sys.path().insert(int32(0), py_dir);
end



%% === Clean-slate toggle ===
fprintf('================================================================\n');
fprintf('  PREPROCESSING MODE\n');
fprintf('================================================================\n');
fprintf('  (1) Full run  — clear all output dirs and reprocess everything\n');
fprintf('  (2) Skip      — skip pixel processing, go straight to pruning\n');
fprintf('================================================================\n');
mode = input('  >> Enter 1 or 2: ', 's');
do_pixel_processing = strcmp(strtrim(mode), '1');

if do_pixel_processing
    % Clear both output directories for every region being processed
    for i = 1:length(countries)
        subdir = countries{i};
        preproc_dir    = [subjects subdir '/preprocessed'];
        unfiltered_dir = [subjects subdir '/unfiltered'];
        for d = {preproc_dir, unfiltered_dir}
            dpath = d{1};
            if exist(dpath, 'dir')
                rmdir(dpath, 's');
                fprintf('Cleared directory: %s\n', dpath);
            end
            mkdir(dpath);
        end
    end

    % Process each region
    for i = 1:length(countries)
        process_region_directory([subjects countries{i}]);
    end
else
    fprintf('\nSkipping pixel processing — using existing output dirs.\n\n');
end

%% === Export subject lists ===
export_subject_lists(subjects, countries);

%% === Generate removal lists (Python) ===
fprintf('\nRunning generate_removal_lists.py...\n');
pyrunfile(fullfile(pwd, 'python_scripts', 'generate_removal_lists.py'));

%% === Apply pruning ===
apply_pruning(subjects, countries);

%% === Export subject lists (post-pruning) ===
fprintf('\n=== Subject counts after pruning ===\n');
export_subject_lists(subjects, countries);

song_count_check(cfg.subjects_dir, cfg.countries);

%% === Build combined_data_all.csv (Python) ===
fprintf('\nRunning build_combined_data.py...\n');
pyrunfile(fullfile(pwd, 'python_scripts', 'build_combined_data.py'));


%% =========================================================
function process_region_directory(basepath)
    fprintf('%s\n', basepath);

    fixSubjectNaming([basepath '/subjects/']);
    generate_presentations([basepath '/subjects/']);
    rename_trials([basepath '/subjects/']);

    subjects = dir([basepath '/subjects/*']);

    base  = uint8(imread('base.png'));
    base2 = base(10:531, 33:203, :);  %#ok<NASGU>
    mask  = imread('mask.png');        %#ok<NASGU>

    for s = 1:length(subjects)
        if subjects(s).name(1) == '.', continue; end

        fprintf('Processing subject %s...\n', subjects(s).name);
        subj_path = [basepath '/subjects/' subjects(s).name];

        pres_file = fullfile(subj_path, 'presentation.txt');
        if ~isfile(pres_file)
            fprintf('  Missing presentation.txt for %s, skipping.\n', subjects(s).name);
            continue;
        end
        filelist = readlines(pres_file);
        filelist = filelist(filelist ~= "");
        NC = numel(filelist);

        data = load_subj(subj_path, 2, subjects(s).name);

        nostalgia_idx    = [];
        control_idx      = [];
        nostalgia_trials = {};
        control_trials   = {};

        for n = 1:NC
            fname = filelist{n};
            if contains(fname, 'Nost')
                nostalgia_idx(end+1)    = n;
                nostalgia_trials{end+1} = fname;
            elseif contains(fname, 'Cont')
                control_idx(end+1)    = n;
                control_trials{end+1} = fname;
            end
        end

        if isempty(nostalgia_idx)
            fprintf('  DISCARDING %s: No nostalgia trials\n', subjects(s).name);
            continue;
        end

        resmat = zeros(522, 171, NC);
        for n = 1:NC
            T    = length(data(n).paint(:,2));
            over = zeros(size(base,1), size(base,2));
            for t = 1:T
                y = max(min(ceil(data(n).paint(t,3)+1), 600), 1);
                x = max(min(ceil(data(n).paint(t,2)+1), 900), 1);
                over(y,x) = over(y,x) + 1;
            end
            h    = fspecial('gaussian', [15 15], 5);
            over = imfilter(over, h);
            resmat(:,:,n) = over(10:531,33:203,:) - over(10:531,696:866,:);
        end

        nostalgia_numbers = extract_trial_numbers(nostalgia_trials, 'Nost');
        control_numbers   = extract_trial_numbers(control_trials,   'Cont');

        %% PIPELINE A: ALL trials -> unfiltered/
        trial_data_all = struct();
        for i = 1:length(nostalgia_idx)
            tname = sprintf('Nost%d', nostalgia_numbers(i));
            trial_data_all.(tname) = resmat(:,:,nostalgia_idx(i));
        end
        for i = 1:length(control_idx)
            tname = sprintf('Cont%d', control_numbers(i));
            trial_data_all.(tname) = resmat(:,:,control_idx(i));
        end
        trial_data_all.nostalgia_avg = mean(resmat(:,:,nostalgia_idx), 3);
        if ~isempty(control_idx)
            trial_data_all.control_avg = mean(resmat(:,:,control_idx), 3);
        end
        save([basepath '/unfiltered/' subjects(s).name '_preprocessed.mat'], '-struct', 'trial_data_all');

        %% PIPELINE B: PAIRED trials only -> preprocessed/
        if isempty(control_idx)
            fprintf('  Skipping paired save for %s: No control trials\n', subjects(s).name);
        else
            common_trials = intersect(nostalgia_numbers, control_numbers);
            if isempty(common_trials)
                fprintf('  Skipping paired save for %s: No matching trial pairs\n', subjects(s).name);
            else
                fprintf('  Found %d valid trial pairs for %s\n', length(common_trials), subjects(s).name);
                trial_data_paired = struct();
                valid_nost_idx    = [];
                valid_cont_idx    = [];

                for i = 1:length(nostalgia_numbers)
                    if ismember(nostalgia_numbers(i), common_trials)
                        tname = sprintf('Nost%d', nostalgia_numbers(i));
                        trial_data_paired.(tname) = resmat(:,:,nostalgia_idx(i));
                        valid_nost_idx(end+1) = nostalgia_idx(i);
                    end
                end
                for i = 1:length(control_numbers)
                    if ismember(control_numbers(i), common_trials)
                        tname = sprintf('Cont%d', control_numbers(i));
                        trial_data_paired.(tname) = resmat(:,:,control_idx(i));
                        valid_cont_idx(end+1) = control_idx(i);
                    end
                end

                trial_data_paired.nostalgia_avg = mean(resmat(:,:,valid_nost_idx), 3);
                trial_data_paired.control_avg   = mean(resmat(:,:,valid_cont_idx), 3);
                trial_data_paired.valid_pairs   = common_trials;
                save([basepath '/preprocessed/' subjects(s).name '_preprocessed.mat'], '-struct', 'trial_data_paired');
            end
        end
    end
end


%% =========================================================
function numbers = extract_trial_numbers(trial_list, prefix)
    numbers = zeros(1, length(trial_list));
    pattern = [prefix '(\d+)'];
    for i = 1:length(trial_list)
        match = regexp(trial_list{i}, pattern, 'tokens');
        if ~isempty(match)
            numbers(i) = str2double(match{1}{1});
        else
            numbers(i) = i;
        end
    end
end


%% =========================================================
function export_subject_lists(base_path, countries)
    out_paired = fullfile(base_path, 'subject_list_preprocessed.csv');
    out_all    = fullfile(base_path, 'subject_list_unfiltered.csv');

    fid_paired = fopen(out_paired, 'w');
    fid_all    = fopen(out_all,    'w');
    fprintf(fid_paired, 'subject,country\n');
    fprintf(fid_all,    'subject,country\n');

    fprintf('\n=== Subject counts after preprocessing ===\n');
    fprintf('%-10s  %12s  %14s\n', 'Country', 'preprocessed', 'unfiltered');
    fprintf('%s\n', repmat('-', 1, 44));

    total_paired = 0; total_all = 0;
    for i = 1:length(countries)
        country = countries{i};
        paired_files = dir(fullfile(base_path, country, 'preprocessed', '*_preprocessed.mat'));
        unf_files    = dir(fullfile(base_path, country, 'unfiltered',   '*_preprocessed.mat'));
        for j = 1:length(paired_files)
            subj_name = strrep(paired_files(j).name, '_preprocessed.mat', '');
            fprintf(fid_paired, '%s,%s\n', subj_name, country);
        end
        for j = 1:length(unf_files)
            subj_name = strrep(unf_files(j).name, '_preprocessed.mat', '');
            fprintf(fid_all, '%s,%s\n', subj_name, country);
        end
        fprintf('%-10s  %12d  %16d\n', country, length(paired_files), length(unf_files));
        total_paired = total_paired + length(paired_files);
        total_all    = total_all    + length(unf_files);
    end
    fprintf('%s\n', repmat('-', 1, 44));
    fprintf('%-10s  %12d  %16d\n', 'TOTAL', total_paired, total_all);
    fclose(fid_paired); fclose(fid_all);
    fprintf('Subject lists written to:\n  %s\n  %s\n', out_paired, out_all);
end


%% =========================================================
%% This function allows the user to provide a .csv of subjects to be not included in analysis
%% Default behavior is to truncate subjects so each country has equal contribution (i.e. 60 subjects per country)
function apply_pruning(base_path, countries)

    function chosen = prompt_for_csv(base_path, pipeline_label, default_filename)
        fprintf('\n--- Pruning for %s pipeline ---\n', pipeline_label);
        fprintf('  [1] Use default (%s)\n', default_filename);
        fprintf('  [2] Skip pruning\n');
        fprintf('  [3] Enter custom filename\n');

        while true
            sel = input('  >> Enter 1, 2, or 3: ', 's');
            switch strtrim(sel)
                case '1'
                    chosen = fullfile(base_path, default_filename);
                    if ~isfile(chosen)
                        fprintf('  ERROR: Default file not found: %s\n', chosen);
                        fprintf('  Please choose another option.\n');
                        continue;
                    end
                    fprintf('  Using: %s\n', default_filename);
                    return;
                case '2'
                    chosen = '';
                    fprintf('  Skipping pruning for %s pipeline.\n', pipeline_label);
                    return;
                case '3'
                    fname = input('  >> Enter filename (relative to subjects dir): ', 's');
                    chosen = fullfile(base_path, strtrim(fname));
                    if ~isfile(chosen)
                        fprintf('  ERROR: File not found: %s\n', chosen);
                        fprintf('  Please try again.\n');
                        continue;
                    end
                    fprintf('  Using: %s\n', fname);
                    return;
                otherwise
                    fprintf('  Invalid selection, please enter 1, 2, or 3.\n');
            end
        end
    end

    remove_paired_file = prompt_for_csv(base_path, 'paired (preprocessed/)', 'preprocessing_remove_paired.csv');
    remove_all_file    = prompt_for_csv(base_path, 'unfiltered',             'preprocessing_remove_unfiltered.csv');

    function delete_subject_mat(dir_path, subj_name)
        mat_file = fullfile(dir_path, [char(subj_name) '_preprocessed.mat']);
        if isfile(mat_file)
            delete(mat_file);
            fprintf('    Removed: %s\n', mat_file);
        else
            fprintf('    Not found (skipping): %s\n', mat_file);
        end
    end

    if ~isempty(remove_paired_file)
        remove_paired = readtable(remove_paired_file, 'TextType', 'string');
        fprintf('\n--- Applying paired (preprocessed/) removals ---\n');
        for i = 1:height(remove_paired)
            subj    = remove_paired.subject(i);
            country = remove_paired.country(i);
            delete_subject_mat(fullfile(base_path, country, 'preprocessed'), subj);
            delete_subject_mat(fullfile(base_path, 'all',   'preprocessed'), subj);
        end
    else
        fprintf('\n--- Skipped paired (preprocessed/) pruning ---\n');
    end

    if ~isempty(remove_all_file)
        remove_all = readtable(remove_all_file, 'TextType', 'string');
        fprintf('\n--- Applying unfiltered (unfiltered/) removals ---\n');
        for i = 1:height(remove_all)
            subj    = remove_all.subject(i);
            country = remove_all.country(i);
            delete_subject_mat(fullfile(base_path, country, 'unfiltered'), subj);
            delete_subject_mat(fullfile(base_path, 'all',   'unfiltered'), subj);
        end
    else
        fprintf('\n--- Skipped unfiltered pruning ---\n');
    end

    fprintf('\nPruning complete.\n');
end

%% =========================================================
function song_count_check(subjects_dir, countries)
%Tally nostalgia/control trial counts per subject
    fprintf('\n=== Song count check ===\n');
    pipelines = {'preprocessed', 'unfiltered'};

    for p = 1:numel(pipelines)
        pipeline   = pipelines{p};
        total_nost = 0;
        total_cont = 0;
        n_subjects = 0;
        n_flagged  = 0;

        for i = 1:numel(countries)
            country = countries{i};
            if strcmp(country, 'all'), continue; end  % avoid double-counting the aggregate dir

            dir_path = fullfile(subjects_dir, country, pipeline);
            files    = dir(fullfile(dir_path, '*_preprocessed.mat'));

            for j = 1:numel(files)
                s  = load(fullfile(dir_path, files(j).name));
                fn = fieldnames(s);

                nost_count = sum(~cellfun('isempty', regexp(fn, '^Nost\d+$', 'once')));
                cont_count = sum(~cellfun('isempty', regexp(fn, '^Cont\d+$', 'once')));

                total_nost = total_nost + nost_count;
                total_cont = total_cont + cont_count;
                n_subjects = n_subjects + 1;

                subj_name = strrep(files(j).name, '_preprocessed.mat', '');

                if strcmp(pipeline, 'preprocessed')
                    if nost_count ~= cont_count
                        fprintf('  [FLAG] %s (%s): Nost=%d, Cont=%d — expected equal paired counts\n', ...
                            subj_name, country, nost_count, cont_count);
                        n_flagged = n_flagged + 1;
                    end
                else % unfiltered
                    if nost_count < 4
                        fprintf('  [FLAG] %s (%s): Nost=%d — expected at least 4 nostalgia trials\n', ...
                            subj_name, country, nost_count);
                        n_flagged = n_flagged + 1;
                    end
                end
            end
        end

        total_songs = total_nost + total_cont;
        fprintf('\n%s pipeline: %d subjects, %d nostalgia trials, %d control trials, %d total songs\n', ...
            pipeline, n_subjects, total_nost, total_cont, total_songs);

        if n_flagged > 0
            fprintf('  %d subject(s) flagged for anomalous counts (see [FLAG] lines above)\n', n_flagged);
        else
            fprintf('  All subjects passed count check.\n');
        end
    end
end