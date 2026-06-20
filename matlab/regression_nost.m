%% PCA + Regression: Bodily Sensation ~ Positive/Negative Feelings
%  (Subject-level, nostalgia trials only)
%
% Matches the validation logic of pixel_regression (subject-level) script:
%   - Uses cfg = read_config() for all paths
%   - Uses combined_data_all.csv (cfg.regression_csv) for ratings
%   - Each subject is required to have all 4 nostalgia trials with valid
%     (non-blank, non-DATA_EXPIRED) pos/neg ratings, since by study design
%     every subject completes exactly 4 nostalgia trials. Subjects failing
%     this check are reported and excluded, NOT silently dropped.
%   - One row per SUBJECT (using nostalgia_avg pixel data), not per trial.
%   - Control trials are NOT used anywhere in this script.

clear; clc;

%% ── 0.  Config / paths ───────────────────────────────────────────────────
cfg = read_config();

pictures_dir = cfg.pic_regression;
if ~exist(pictures_dir, 'dir')
    mkdir(pictures_dir);
    fprintf('Created directory: %s\n', pictures_dir);
end

data_dir = fullfile(cfg.subjects_dir, 'all', 'unfiltered');
csv_path = cfg.combined_csv;

IMG_H = 522;
IMG_W = 171;

%% ── 1.  Load mask ────────────────────────────────────────────────────────
mask = imread('mask.png');
if ndims(mask) == 3, mask = mask(:,:,1); end
in_mask = find(mask > 128);
fprintf('Mask dimensions: %d x %d | Pixels inside mask: %d\n', ...
    size(mask,1), size(mask,2), numel(in_mask));

%% ── 2.  Load survey CSV ──────────────────────────────────────────────────
fprintf('Loading survey data from %s ...\n', csv_path);
opts = detectImportOptions(csv_path, 'TextType', 'string', ...
                           'VariableNamingRule', 'preserve');
survey = readtable(csv_path, opts);

ids  = string(survey.('ID'));
pids = string(survey.('PROLIFIC_PID'));

id_map  = containers.Map(ids,  num2cell(1:height(survey)));
pid_map = containers.Map(pids, num2cell(1:height(survey)));

%% ── 3.  List .mat files ──────────────────────────────────────────────────
fprintf('Scanning .mat files in %s ...\n', data_dir);
mat_files = dir(fullfile(data_dir, '*.mat'));
if isempty(mat_files)
    error('No .mat files found in %s', data_dir);
end

%% ── 4.  Per-subject pass: validate 4/4 nostalgia trials, average ratings ──
n_subj_total  = numel(mat_files);
subj_id       = strings(n_subj_total,1);
subj_pixel    = nan(IMG_H, IMG_W, n_subj_total);
subj_pos_mean = nan(n_subj_total,1);
subj_neg_mean = nan(n_subj_total,1);
keep          = false(n_subj_total,1);

n_skipped_nomatch   = 0;
n_skipped_badrating = 0;
n_skipped_nofield   = 0;

bad_rating_log = {};  % {filename, missing_fields}

for f = 1:n_subj_total
    mat_path = fullfile(data_dir, mat_files(f).name);
    [~, fname] = fileparts(mat_files(f).name);

    cand = unique(string({ ...
        fname, ...
        regexprep(fname, '_(unfiltered|preprocessed|subjects)$', ''), ...
        char(extractBefore(string(fname) + "_", "_")) ...
    }), 'stable');

    row = [];
    for c = 1:numel(cand)
        key = cand(c);
        if isKey(id_map, key)
            row = id_map(key);  break
        elseif isKey(pid_map, key)
            row = pid_map(key); break
        end
    end
    if isempty(row)
        n_skipped_nomatch = n_skipped_nomatch + 1;
        continue
    end

    S = load(mat_path);
    if ~isfield(S, 'nostalgia_avg')
        n_skipped_nofield = n_skipped_nofield + 1;
        continue
    end
    pix = S.nostalgia_avg;
    if ~isequal(size(pix), [IMG_H, IMG_W])
        warning('Unexpected nostalgia_avg size for %s - skipping', fname);
        n_skipped_nofield = n_skipped_nofield + 1;
        continue
    end

    % Require ALL 4 nostalgia trials to have valid pos AND neg ratings.
    pos_vals = nan(1,4);
    neg_vals = nan(1,4);
    missing_fields = {};
    for k = 1:4
        pfx = sprintf('N%d', k);
        pos_vals(k) = read_rating(survey, [pfx '_pos'], row);
        neg_vals(k) = read_rating(survey, [pfx '_neg'], row);
        if isnan(pos_vals(k)), missing_fields{end+1} = [pfx '_pos']; end %#ok<AGROW>
        if isnan(neg_vals(k)), missing_fields{end+1} = [pfx '_neg']; end %#ok<AGROW>
    end

    if ~isempty(missing_fields)
        n_skipped_badrating = n_skipped_badrating + 1;
        bad_rating_log(end+1,:) = {fname, strjoin(missing_fields, ',')}; %#ok<AGROW>
        continue
    end

    subj_id(f)        = fname;
    subj_pixel(:,:,f) = pix;
    subj_pos_mean(f)  = mean(pos_vals);
    subj_neg_mean(f)  = mean(neg_vals);
    keep(f)           = true;
end

fprintf('\n--- SUBJECT VALIDATION SUMMARY ---\n');
fprintf('Total .mat files scanned        : %d\n', n_subj_total);
fprintf('Skipped (no CSV match)          : %d\n', n_skipped_nomatch);
fprintf('Skipped (missing nostalgia_avg) : %d\n', n_skipped_nofield);
fprintf('Skipped (incomplete 4/4 ratings): %d\n', n_skipped_badrating);
fprintf('Included subjects (N)           : %d\n', nnz(keep));
fprintf('-----------------------------------\n\n');

if ~isempty(bad_rating_log)
    fprintf('Subjects excluded for missing/blank nostalgia ratings:\n');
    for i = 1:size(bad_rating_log,1)
        fprintf('  %s : missing %s\n', bad_rating_log{i,1}, bad_rating_log{i,2});
    end
    fprintf('\n');
end

n_subj = nnz(keep);
if n_subj == 0
    error('No subjects passed validation. Check filename-to-CSV matching and rating columns.');
end

subj_id       = subj_id(keep);
subj_pixel    = subj_pixel(:,:,keep);
subj_pos_mean = subj_pos_mean(keep);
subj_neg_mean = subj_neg_mean(keep);

% Each row here is ONE subject -- df = n_subj - num_components - 1
% downstream, matching the number of independent units of information.

%% ── 5.  Build [n_subj x n_in_mask] data matrix ────────────────────────────
n_in_mask = numel(in_mask);
data = nan(n_subj, n_in_mask);
for s = 1:n_subj
    pix = subj_pixel(:,:,s);
    data(s,:) = pix(in_mask)';
end

%% ── 6.  PCA ─────────────────────────────────────────────────────────────
num_components = min(30, n_subj - 1);
[coeff, score, ~, ~, explained] = pca(data, 'NumComponents', num_components);
fprintf('PC1 = %.1f%%  PC2 = %.1f%%  PC3 = %.1f%%\n', explained(1), explained(2), explained(3));

%% ── 7.  Regression (subject-level) ─────────────────────────────────────
pos_values     = subj_pos_mean(:);
neg_values     = subj_neg_mean(:);
min_values     = min(pos_values, neg_values);
griffin_values = (pos_values + neg_values)/2 + abs(pos_values - neg_values);

pos_values     = pos_values     - mean(pos_values,     'omitnan');
neg_values     = neg_values     - mean(neg_values,     'omitnan');
min_values     = min_values     - mean(min_values,     'omitnan');
griffin_values = griffin_values - mean(griffin_values, 'omitnan');

pos_reg     = fitlm(score, pos_values);
neg_reg     = fitlm(score, neg_values);
min_reg     = fitlm(score, min_values);
griffin_reg = fitlm(score, griffin_values);

fprintf('\nR² (N=%d subjects) — Pos: %.3f  Neg: %.3f  Min: %.3f  Griffin: %.3f\n', ...
    n_subj, pos_reg.Rsquared.Adjusted, neg_reg.Rsquared.Adjusted, ...
    min_reg.Rsquared.Adjusted, griffin_reg.Rsquared.Adjusted);

%% ── 8.  Colormap ─────────────────────────────────────────────────────────
M      = 0.05;
NumCol = 64;
hotmap = hot(NumCol);
coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
hotcoldmap = [coldmap; hotmap];

%% ── 9.  PCA overview figure ────────────────────────────────────────────
fig_pca = figure;
subplot(1,2,1); plot(score(:,1), score(:,2), 'o');
xlabel('PC1'); ylabel('PC2'); title(sprintf('Nostalgia subjects in PCA space (N=%d)', n_subj));
subplot(1,2,2); bar(explained(1:min(10,num_components)));
xlabel('PC'); ylabel('Variance (%)'); title('Variance explained');
saveas(fig_pca, fullfile(pictures_dir, [cfg.pic_prefix 'pca_overview_subjectlevel.png']));

%% ── 10. Map regression weights back to pixel space ────────────────────
beta_pos     = pos_reg.Coefficients.Estimate(2:end);
beta_neg     = neg_reg.Coefficients.Estimate(2:end);
beta_min     = min_reg.Coefficients.Estimate(2:end);
beta_griffin = griffin_reg.Coefficients.Estimate(2:end);

pixel_beta_pos     = coeff * beta_pos;
pixel_beta_neg     = coeff * beta_neg;
pixel_beta_min     = coeff * beta_min;
pixel_beta_griffin = coeff * beta_griffin;

pos_img     = make_img(mask, in_mask, pixel_beta_pos);
neg_img     = make_img(mask, in_mask, pixel_beta_neg);
min_img     = make_img(mask, in_mask, pixel_beta_min);
griffin_img = make_img(mask, in_mask, pixel_beta_griffin);

fig_reg = figure;
subplot(2,2,1); imagesc(pos_img,[-M M]); axis image off; colormap(hotcoldmap); colorbar; title('Positive (pixel)');
subplot(2,2,2); imagesc(neg_img,[-M M]); axis image off; colormap(hotcoldmap); colorbar; title('Negative (pixel)');
subplot(2,2,3); imagesc(min_img,[-M M]); axis image off; colormap(hotcoldmap); colorbar; title('Min (pixel)');
subplot(2,2,4); imagesc(griffin_img,[-M M]); axis image off; colormap(hotcoldmap); colorbar; title('Griffin (pixel)');
sgtitle(sprintf('PCA Regression Maps (Subject-level, N=%d, Nostalgia only)', n_subj));
saveas(fig_reg, fullfile(pictures_dir, [cfg.pic_prefix 'regression_maps_subjectlevel.png']));

%% ── 11. PC maps ─────────────────────────────────────────────────────────
fig_pc = figure;
for k = 1:min(6, num_components)
    pc_img = make_img(mask, in_mask, coeff(:,k));
    subplot(2,3,k); imagesc(pc_img,[-M M]); axis image off;
    colormap(hotcoldmap); colorbar; title(sprintf('PC%d',k));
end
saveas(fig_pc, fullfile(pictures_dir, [cfg.pic_prefix 'pc_maps_subjectlevel.png']));

%% ── 12. Save results ───────────────────────────────────────────────────
save(fullfile(pictures_dir, 'pca_regression_results_subjectlevel.mat'), ...
     'coeff','score','explained', ...
     'pos_reg','neg_reg','min_reg','griffin_reg', ...
     'pixel_beta_pos','pixel_beta_neg','pixel_beta_min','pixel_beta_griffin', ...
     'subj_id','n_subj');

fprintf('\nAll figures saved to: %s\n', pictures_dir);


%% ═══════════════════════════════════════════════════════════════════════
%  LOCAL FUNCTIONS
%% ═══════════════════════════════════════════════════════════════════════

function v = read_rating(survey, colname, row)
% Returns a numeric rating, or NaN if the column is missing / DATA_EXPIRED / blank.
    if ~ismember(colname, survey.Properties.VariableNames)
        v = NaN; return
    end
    raw = survey.(colname)(row);
    if iscell(raw), raw = raw{1}; end
    if isstring(raw) || ischar(raw)
        s = string(raw);
        if s=="" || s=="DATA_EXPIRED", v = NaN; return; end
        v = str2double(s);
    else
        v = double(raw);
    end
    if isnan(v), return; end
end

function img = make_img(mask, in_mask, vals)
    img = nan(size(mask));
    img(in_mask) = vals;
end