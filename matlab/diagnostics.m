%% diagnostics.m
% Run this in the same working directory as pixel_regression.m
% Validates the match between .mat files and the CSV, and checks internal
% consistency of every subject's data before any regression is run.

clear; clc;

%% ── Paths (must match pixel_regression.m) ───────────────────────────────

data_dir  = fullfile('final&new_subjects', 'all', 'unfiltered');
csv_path  = 'combined_data_all.csv';

EXPECTED_NOST_TRIALS  = 4;       % every subject should have Nost1..Nost4
EXPECTED_RATINGS_COLS = {'N1_pos','N1_neg','N2_pos','N2_neg', ...
                          'N3_pos','N3_neg','N4_pos','N4_neg'};
IMG_H = 522;
IMG_W = 171;

%% ── 1.  Load CSV ─────────────────────────────────────────────────────────
fprintf('=== Loading CSV ===\n');
opts = detectImportOptions(csv_path, 'TextType','string', ...
                           'VariableNamingRule','preserve');
survey = readtable(csv_path, opts);
fprintf('CSV rows : %d\n', height(survey));
fprintf('CSV cols : %d\n', width(survey));

ids  = string(survey.('ID'));
pids = string(survey.('PROLIFIC_PID'));
id_map  = containers.Map(ids,  num2cell(1:height(survey)));
pid_map = containers.Map(pids, num2cell(1:height(survey)));

% Check that every expected ratings column is present
fprintf('\n--- Required rating columns present? ---\n');
all_cols_present = true;
for c = 1:numel(EXPECTED_RATINGS_COLS)
    col = EXPECTED_RATINGS_COLS{c};
    present = ismember(col, survey.Properties.VariableNames);
    if ~present
        fprintf('  MISSING COLUMN: %s\n', col);
        all_cols_present = false;
    end
end
if all_cols_present
    fprintf('  All 8 rating columns (N1..N4 pos/neg) found.\n');
end

%% ── 2.  List .mat files ──────────────────────────────────────────────────
fprintf('\n=== Scanning .mat files ===\n');
mat_files = dir(fullfile(data_dir, '*.mat'));
NS = numel(mat_files);
fprintf('Found %d .mat files\n', NS);

%% ── 3.  Per-subject validation ───────────────────────────────────────────
fprintf('\n=== Per-subject validation ===\n');
fprintf('%-30s  %-8s  %-10s  %-10s  %-12s  %s\n', ...
        'Subject key', 'CSV row', 'Nost count', 'Size OK?', 'Ratings OK?', 'Issues');
fprintf('%s\n', repmat('-',1,100));

% Accumulators for summary
n_no_match        = 0;
n_wrong_nost      = 0;
n_bad_size        = 0;
n_missing_ratings = 0;

skipped_subjects   = {};
wrong_nost_subs    = {};
bad_size_subs      = {};
missing_rating_log = {};   % cell of strings

for f = 1:NS
    [~, fname] = fileparts(mat_files(f).name);

    % Key candidates (same logic as regression script)
    cand = unique(string({ ...
        fname, ...
        regexprep(fname, '_(unfiltered|preprocessed|subjects)$',''), ...
        char(extractBefore(string(fname)+"_","_")) ...
    }), 'stable');

    row = [];
    matched_key = '';
    for c = 1:numel(cand)
        key = cand(c);
        if isKey(id_map,  key), row = id_map(key);  matched_key = key; break; end
        if isKey(pid_map, key), row = pid_map(key); matched_key = key; break; end
    end

    % ── No CSV match ──────────────────────────────────────────────────────
    if isempty(row)
        n_no_match = n_no_match + 1;
        skipped_subjects{end+1} = struct( ...
            'filename', mat_files(f).name, ...
            'candidates_tried', strjoin(cand, ' | '));
        fprintf('%-30s  %-8s  %-10s  %-10s  %-12s  %s\n', ...
                strtrim(mat_files(f).name(1:min(28,end))), ...
                'NO MATCH', '-', '-', '-', 'NOT IN CSV');
        continue
    end

    % ── Load .mat ─────────────────────────────────────────────────────────
    S = load(fullfile(data_dir, mat_files(f).name));

    % Count Nost fields and check sizes
    nost_fields = fieldnames(S);
    nost_fields = nost_fields(~cellfun('isempty', ...
        regexp(nost_fields, '^Nost\d+$')));
    n_nost = numel(nost_fields);

    size_issues = {};
    for nf = 1:numel(nost_fields)
        sz = size(S.(nost_fields{nf}));
        if ~isequal(sz, [IMG_H, IMG_W])
            size_issues{end+1} = sprintf('%s:%dx%d', nost_fields{nf}, sz(1), sz(2));
        end
    end

    % ── Check ratings in CSV ──────────────────────────────────────────────
    rating_issues = {};
    for c = 1:numel(EXPECTED_RATINGS_COLS)
        col = EXPECTED_RATINGS_COLS{c};
        if ~ismember(col, survey.Properties.VariableNames)
            rating_issues{end+1} = [col '(col missing)'];
            continue
        end
        raw = survey.(col)(row);
        if iscell(raw), raw = raw{1}; end
        if isstring(raw) || ischar(raw)
            s = string(raw);
            if s=="" || s=="DATA_EXPIRED"
                val = NaN;
            else
                val = str2double(s);
            end
        else
            val = double(raw);
        end
        if isnan(val)
            rating_issues{end+1} = [col '=NaN'];
        end
    end

    % ── Build issue string ────────────────────────────────────────────────
    issues = {};
    if n_nost ~= EXPECTED_NOST_TRIALS
        issues{end+1} = sprintf('Nost count=%d (expected %d)', n_nost, EXPECTED_NOST_TRIALS);
        n_wrong_nost = n_wrong_nost + 1;
        wrong_nost_subs{end+1} = struct('subject', matched_key, ...
            'n_nost', n_nost, 'fields', {nost_fields'});
    end
    if ~isempty(size_issues)
        issues{end+1} = ['BadSize:' strjoin(size_issues,',')];
        n_bad_size = n_bad_size + 1;
        bad_size_subs{end+1} = matched_key;
    end
    if ~isempty(rating_issues)
        issues{end+1} = ['MissingRatings:' strjoin(rating_issues,',')];
        n_missing_ratings = n_missing_ratings + 1;
        missing_rating_log{end+1} = struct('subject', matched_key, 'issues', {rating_issues});
    end

    issue_str = strjoin(issues, ' | ');
    if isempty(issue_str), issue_str = 'OK'; end

    % Only print problem rows to keep output readable; comment the if/end to
    % print every subject.
    if ~isempty(issues)
        fprintf('%-30s  %-8d  %-10d  %-10s  %-12s  %s\n', ...
                matched_key(1:min(28,strlength(matched_key))), row, n_nost, ...
                ternary(isempty(size_issues),'yes','NO'), ...
                ternary(isempty(rating_issues),'yes','NO'), ...
                issue_str);
    end
end

%% ── 4.  Summary ──────────────────────────────────────────────────────────
fprintf('\n%s\n', repmat('=',1,60));
fprintf('SUMMARY\n');
fprintf('%s\n', repmat('=',1,60));
fprintf('Total .mat files examined      : %d\n', NS);
fprintf('No CSV match (skipped)         : %d\n', n_no_match);
fprintf('Wrong Nost trial count         : %d\n', n_wrong_nost);
fprintf('Wrong pixel dimensions         : %d\n', n_bad_size);
fprintf('Missing/NaN ratings in CSV     : %d\n', n_missing_ratings);
fprintf('Clean subjects (all checks OK) : %d\n', ...
        NS - n_no_match - n_wrong_nost - n_bad_size - n_missing_ratings);

%% ── 5.  Detail blocks ────────────────────────────────────────────────────

% -- Skipped subjects --
if ~isempty(skipped_subjects)
    fprintf('\n--- Subjects with NO CSV match (%d) ---\n', numel(skipped_subjects));
    for k = 1:numel(skipped_subjects)
        fprintf('  File     : %s\n', skipped_subjects{k}.filename);
        fprintf('  Tried    : %s\n\n', skipped_subjects{k}.candidates_tried);
    end
    fprintf('ACTION: Verify these IDs exist in combined_data_all.csv.\n');
    fprintf('        Check the "Sample CSV ID" and "Sample .mat filenames"\n');
    fprintf('        printed above to confirm the naming convention matches.\n');
end

% -- Wrong Nost trial count --
if ~isempty(wrong_nost_subs)
    fprintf('\n--- Subjects with wrong Nost trial count (%d) ---\n', numel(wrong_nost_subs));
    for k = 1:numel(wrong_nost_subs)
        fprintf('  Subject : %s\n', wrong_nost_subs{k}.subject);
        fprintf('  Count   : %d  (expected %d)\n', wrong_nost_subs{k}.n_nost, EXPECTED_NOST_TRIALS);
        fprintf('  Fields  : %s\n\n', strjoin(wrong_nost_subs{k}.fields, ', '));
    end
    fprintf('ACTION: Re-check the preprocessing pipeline for these subjects.\n');
end

% -- Missing ratings --
if ~isempty(missing_rating_log)
    fprintf('\n--- Subjects with missing/NaN ratings (%d) ---\n', numel(missing_rating_log));
    for k = 1:numel(missing_rating_log)
        fprintf('  Subject : %s\n', missing_rating_log{k}.subject);
        fprintf('  Issues  : %s\n\n', strjoin(missing_rating_log{k}.issues, ', '));
    end
    fprintf('ACTION: Inspect combined_data_all.csv rows for these subjects.\n');
end

%% ── 6.  Cross-check: every CSV subject that has a .mat should have ratings ─
fprintf('\n=== Reverse check: CSV subjects missing .mat files ===\n');
all_mat_keys = string({mat_files.name}');
all_mat_keys = regexprep(all_mat_keys, '_(unfiltered|preprocessed|subjects)\.mat$','');
all_mat_keys = regexprep(all_mat_keys, '\.mat$','');

n_csv_no_mat = 0;
for r = 1:height(survey)
    key_id  = ids(r);
    key_pid = pids(r);
    in_mat = any(all_mat_keys == key_id) || any(all_mat_keys == key_pid);
    if ~in_mat
        n_csv_no_mat = n_csv_no_mat + 1;
        if n_csv_no_mat <= 10   % cap output
            fprintf('  CSV row %d  ID=%s  PID=%s  -> no .mat found\n', ...
                    r, key_id, key_pid);
        end
    end
end
if n_csv_no_mat > 10
    fprintf('  ... and %d more.\n', n_csv_no_mat-10);
end
if n_csv_no_mat == 0
    fprintf('  All CSV subjects have a corresponding .mat file.\n');
end

fprintf('\nDiagnostics complete.\n');

%% ── 7.  Cross-check: preprocessed subject list vs combined_data_all.csv ──────
fprintf('\n=== Cross-check: subject_list_preprocessed vs combined_data_all.csv ===\n');

subj_list_path = fullfile('final&new_subjects', 'subject_list_preprocessed.csv');

if ~isfile(subj_list_path)
    fprintf('  WARNING: %s not found, skipping this check.\n', subj_list_path);
else
    opts2 = detectImportOptions(subj_list_path, 'TextType', 'string', ...
                                'VariableNamingRule', 'preserve');
    subj_list = readtable(subj_list_path, opts2);
    fprintf('  Rows in subject_list_preprocessed.csv : %d\n', height(subj_list));

    % Deduplicate — the 'all' country repeats every ID
    list_ids = unique(string(subj_list.('subject')));
    fprintf('  Unique subject IDs in list            : %d\n', numel(list_ids));

    % IDs present in the combined CSV
    csv_ids_set = string(survey.('ID'));

    % Find which listed subjects are absent from the CSV
    missing_mask = ~ismember(list_ids, csv_ids_set);
    missing_ids  = list_ids(missing_mask);

    fprintf('  Subjects in list also in CSV          : %d\n', numel(list_ids) - numel(missing_ids));
    fprintf('  Subjects in list but MISSING from CSV : %d\n', numel(missing_ids));

    if ~isempty(missing_ids)
        fprintf('\n  --- Missing subject IDs ---\n');
        for k = 1:numel(missing_ids)
            fprintf('    %s\n', missing_ids(k));
        end

        % Break down by country (using the per-country rows, not 'all')
        country_rows = subj_list(subj_list.('country') ~= "all", :);
        fprintf('\n  --- Missing subjects by country ---\n');
        countries_present = unique(string(country_rows.('country')));
        for c = 1:numel(countries_present)
            cname     = countries_present(c);
            c_ids     = string(country_rows.('subject')(string(country_rows.('country')) == cname));
            c_missing = c_ids(~ismember(c_ids, csv_ids_set));
            fprintf('    %s : %d missing out of %d\n', cname, numel(c_missing), numel(c_ids));
        end

        fprintf('\n  ACTION: These subjects have preprocessed .mat files and are in\n');
        fprintf('          subject_list_preprocessed.csv, but were never written into\n');
        fprintf('          combined_data_all.csv. Re-run build_combined_data.py and\n');
        fprintf('          check whether it scans ''preprocessed'' vs ''unfiltered'' dirs.\n');
    else
        fprintf('  All listed subjects are present in combined_data_all.csv.\n');
    end
end
%% ── Helper ───────────────────────────────────────────────────────────────
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end