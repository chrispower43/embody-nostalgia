%% Combined emBODY preprocessing script
%  Runs two pipelines in one pass per subject:
%    - Paired trials only  -> <region>/preprocessed/
%    - All trials          -> <region>/unfiltered/
close all
clear

countries = {'BR','IN','US','SP', 'JP', 'all'};

subjects = ['final&new_subjects/'];

% Clear both output directories for every region being processed
for i = 1:length(countries)
    subdir = countries{i};

    preproc_dir     = [subjects subdir '/preprocessed'];
    unfiltered_dir  = [subjects subdir '/unfiltered'];

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
    subdir = countries{i};
    process_region_directory([subjects subdir]);
end

%% === Export subject lists ===
% Writes subject_list_preprocessed.csv and subject_list_unfiltered.csv
% and prints counts before pruning.
export_subject_lists(subjects, countries);

%% === Pruning pause ===
fprintf('\n');
fprintf('================================================================\n');
fprintf('  PRUNING STEP\n');
fprintf('================================================================\n');
fprintf('  Subject lists have been exported to:\n');
fprintf('    final&new_subjects/subject_list_preprocessed.csv\n');
fprintf('    final&new_subjects/subject_list_unfiltered_preprocessed.csv\n');
fprintf('\n');
fprintf('  Please now switch to Python and run prune_subjects.py.\n');
fprintf('  This will generate:\n');
fprintf('    final&new_subjects/preprocessing_remove_paired.csv\n');
fprintf('    final&new_subjects/preprocessing_remove_unfiltered.csv\n');
fprintf('\n');
fprintf('  Once both files exist, press Enter here to continue.\n');
fprintf('================================================================\n');
input('  >> Press Enter to continue with pruning: ', 's');

%% === Apply pruning ===
apply_pruning(subjects, countries);

%% === Export subject lists (post-pruning) ===
fprintf('\n=== Subject counts after pruning ===\n');
export_subject_lists(subjects, countries);


%% =========================================================
function process_region_directory(basepath)
%  For every subject in basepath/subjects/ this function:
%    1. Reconstructs per-trial body maps (resmat)
%    2. Saves ALL trials + averages to  basepath/unfiltered/
%    3. Saves only PAIRED trials + averages to basepath/preprocessed/

    fprintf('%s\n', basepath);

    % Run renaming and setup helpers first, so that subjects dir() reflects
    % the final folder names (e.g. after R_ prefix removal by fixSubjectNaming)
    fixSubjectNaming([basepath '/subjects/']);
    generate_presentations([basepath '/subjects/']);
    rename_trials([basepath '/subjects/']);

    subjects = dir([basepath '/subjects/*']);

    base  = uint8(imread('base.png'));
    base2 = base(10:531, 33:203, :);  %#ok<NASGU>  kept for visualisation
    mask  = imread('mask.png');        %#ok<NASGU>  kept for visualisation

    for s = 1:length(subjects)
        if subjects(s).name(1) == '.'
            continue;
        end

        fprintf('Processing subject %s...\n', subjects(s).name);
        subj_path = [basepath '/subjects/' subjects(s).name];

        %% --- Load presentation order ---
        pres_file = fullfile(subj_path, 'presentation.txt');
        if ~isfile(pres_file)
            fprintf('  Missing presentation.txt for %s, skipping.\n', subjects(s).name);
            continue;
        end
        filelist = readlines(pres_file);
        filelist = filelist(filelist ~= "");
        NC = numel(filelist);

        %% --- Load subject data ---
        data = load_subj(subj_path, 2, subjects(s).name);

        %% --- Identify condition types from filenames ---
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

        %% --- Must have at least nostalgia trials to be useful ---
        if isempty(nostalgia_idx)
            fprintf('  DISCARDING %s: No nostalgia trials\n', subjects(s).name);
            continue;
        end

        %% --- Reconstruct body maps ---
        % Cropped size: rows 10:531 -> 522 rows, cols 33:203 -> 171 cols
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

        %% --- Extract numeric trial IDs ---
        nostalgia_numbers = extract_trial_numbers(nostalgia_trials, 'Nost');
        control_numbers   = extract_trial_numbers(control_trials,   'Cont');

        %% =====================================================
        %  PIPELINE A: ALL trials  ->  unfiltered/
        %% =====================================================
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

        unfiltered_dir = [basepath '/unfiltered/'];
        save([unfiltered_dir subjects(s).name '_preprocessed.mat'], '-struct', 'trial_data_all');

        %% =====================================================
        %  PIPELINE B: PAIRED trials only  ->  preprocessed/
        %% =====================================================
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

                preproc_dir = [basepath '/preprocessed/'];
                save([preproc_dir subjects(s).name '_preprocessed.mat'], '-struct', 'trial_data_paired');
            end
        end

    end % subject loop
end % process_region_directory


%% =========================================================
function numbers = extract_trial_numbers(trial_list, prefix)
%  Pull the numeric suffix from filenames like 'Nost03', 'Cont1', etc.
%  Falls back to the list index if no number is found.
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
%  Scans preprocessed/ and unfiltered/ for each country, collects
%  subject names, writes two CSV files, and prints counts to console.
%
%  Output files (written to base_path root):
%    subject_list_preprocessed.csv  -- paired-only pipeline
%    subject_list_unfiltered.csv    -- all-trials pipeline
%
%  CSV format:
%    subject,country

    out_paired = fullfile(base_path, 'subject_list_preprocessed.csv');
    out_all    = fullfile(base_path, 'subject_list_unfiltered.csv');

    fid_paired = fopen(out_paired, 'w');
    fid_all    = fopen(out_all,    'w');

    fprintf(fid_paired, 'subject,country\n');
    fprintf(fid_all,    'subject,country\n');

    fprintf('\n=== Subject counts after preprocessing ===\n');
    fprintf('%-10s  %12s  %14s\n', 'Country', 'preprocessed', 'unfiltered');
    fprintf('%s\n', repmat('-', 1, 44));

    total_paired = 0;
    total_all    = 0;

    for i = 1:length(countries)
        country = countries{i};

        paired_dir = fullfile(base_path, country, 'preprocessed');
        unf_dir    = fullfile(base_path, country, 'unfiltered');

        % Collect paired subjects
        paired_files = dir(fullfile(paired_dir, '*_preprocessed.mat'));
        n_paired = length(paired_files);
        for j = 1:n_paired
            subj_name = strrep(paired_files(j).name, '_preprocessed.mat', '');
            fprintf(fid_paired, '%s,%s\n', subj_name, country);
        end

        % Collect unfiltered subjects
        unf_files = dir(fullfile(unf_dir, '*_preprocessed.mat'));
        n_all = length(unf_files);
        for j = 1:n_all
            subj_name = strrep(unf_files(j).name, '_preprocessed.mat', '');
            fprintf(fid_all, '%s,%s\n', subj_name, country);
        end

        fprintf('%-10s  %12d  %16d\n', country, n_paired, n_all);
        total_paired = total_paired + n_paired;
        total_all    = total_all    + n_all;
    end

    fprintf('%s\n', repmat('-', 1, 44));
    fprintf('%-10s  %12d  %16d\n', 'TOTAL', total_paired, total_all);
    fprintf('\n');

    fclose(fid_paired);
    fclose(fid_all);

    fprintf('Subject lists written to:\n  %s\n  %s\n', out_paired, out_all);
    fprintf('  (unfiltered list: subject_list_unfiltered.csv)\n');
end

%% =========================================================
function apply_pruning(base_path, countries)
%  Reads preprocessing_remove_paired.csv and preprocessing_remove_all.csv
%  from base_path, then deletes the corresponding .mat files from:
%    - <country>/preprocessed/        (paired removal list)
%    - <country>/unfiltered/          (unfiltered removal list)
%    - all/preprocessed/              (paired removal list,   aggregate dir)
%    - all/unfiltered/                (unfiltered removal list, aggregate dir)

    remove_paired_file = fullfile(base_path, 'preprocessing_remove_paired.csv');
    remove_all_file    = fullfile(base_path, 'preprocessing_remove_unfiltered.csv');

    % ── Validate files exist ──────────────────────────────────────────────
    if ~isfile(remove_paired_file)
        error('Missing pruning file: %s\nRun prune_subjects.py first.', remove_paired_file);
    end
    if ~isfile(remove_all_file)
        error('Missing pruning file: %s\nRun prune_subjects.py first.', remove_all_file);
    end

    remove_paired = readtable(remove_paired_file, 'TextType', 'string');
    remove_all    = readtable(remove_all_file,    'TextType', 'string');

    % ── Helper: delete a .mat for one subject from one directory ──────────
    function delete_subject_mat(dir_path, subj_name)
        mat_file = fullfile(dir_path, [char(subj_name) '_preprocessed.mat']);
        if isfile(mat_file)
            delete(mat_file);
            fprintf('    Removed: %s\n', mat_file);
        else
            fprintf('    Not found (skipping): %s\n', mat_file);
        end
    end

    % ── Apply paired removals ─────────────────────────────────────────────
    fprintf('\n--- Applying paired (preprocessed/) removals ---\n');
    for i = 1:height(remove_paired)
        subj    = remove_paired.subject(i);
        country = remove_paired.country(i);

        % Remove from country-specific preprocessed/
        delete_subject_mat(fullfile(base_path, country, 'preprocessed'), subj);
        % Remove from aggregate 'all' preprocessed/
        delete_subject_mat(fullfile(base_path, 'all', 'preprocessed'), subj);
    end

    % ── Apply unfiltered removals ─────────────────────────────────────────
    fprintf('\n--- Applying unfiltered (unfiltered/) removals ---\n');
    for i = 1:height(remove_all)
        subj    = remove_all.subject(i);
        country = remove_all.country(i);

        % Remove from country-specific unfiltered/
        delete_subject_mat(fullfile(base_path, country, 'unfiltered'), subj);
        % Remove from aggregate 'all' unfiltered/
        delete_subject_mat(fullfile(base_path, 'all', 'unfiltered'), subj);
    end

    fprintf('\nPruning complete.\n');
end