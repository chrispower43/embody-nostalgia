%% PCA + Regression: Bodily Sensation ~ Positive/Negative Feelings
%  (Subject-level, nostalgia trials only, WITH inferential statistics)
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
%
% Minimum
%   - Minimum calculated as mean(min(trial1pos,trial1neg),
%   min(trial2pos,trial2neg),...)
%
% STATISTICS
%   PCA regression fits ONE model per outcome in PC space
%   (score(n_subj x numPC) -> outcome). Pixel-space beta maps are a
%   deterministic linear transform of that single model's coefficients
%   (pixel_beta = coeff * beta), NOT independent per-pixel regressions.
%   Per-pixel significance is therefore obtained via the delta method:
%       Var(pixel_beta_p) = coeff(p,:) * Cov(beta) * coeff(p,:)'
%   propagating the PC-space coefficient covariance (from fitlm) through
%   the linear PCA projection exactly, rather than treating pixels as
%   independent tests. BH-FDR is then applied across in-mask pixels.
%   PC-level coefficient significance (which components matter) is also
%   reported, FDR-corrected across components per outcome.

clear; clc;

%% ── 0.  Config / paths ───────────────────────────────────────────────────
cfg = read_config();

pictures_dir = cfg.pca_regression;
if ~exist(pictures_dir, 'dir')
    mkdir(pictures_dir);
    fprintf('Created directory: %s\n', pictures_dir);
end

data_dir = fullfile(cfg.subjects_dir, 'all', 'unfiltered');
csv_path = cfg.combined_csv;

IMG_H = 522;
IMG_W = 171;
FDR_Q = 0.05;   % target false discovery rate

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
subj_min_mean = nan(n_subj_total,1);   
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
    subj_min_mean(f)  = mean(min(pos_vals, neg_vals));
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
subj_min_mean = subj_min_mean(keep);

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
min_values     = subj_min_mean(:);
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

%% ── 10b. Pixel-level inferential statistics (delta method) ──────────────
% pixel_beta = coeff * beta is a LINEAR transform of the single PC-space
% regression's coefficients, not a set of independent per-pixel fits.
% We therefore propagate the coefficient covariance from fitlm through the
% projection exactly, rather than running/assuming independent per-pixel
% tests:
%     Var(pixel_beta_p) = coeff(p,:) * Cov(beta) * coeff(p,:)'
% computed as sum((coeff*Cov) .* coeff, 2) to avoid forming an
% n_pixels x n_pixels matrix.

models = struct( ...
    'pos',     pos_reg, ...
    'neg',     neg_reg, ...
    'min',     min_reg, ...
    'griffin', griffin_reg);

pixel_betas = struct( ...
    'pos',     pixel_beta_pos, ...
    'neg',     pixel_beta_neg, ...
    'min',     pixel_beta_min, ...
    'griffin', pixel_beta_griffin);

outcome_names = fieldnames(models);
stats = struct();

fprintf('\n--- PIXEL-LEVEL FDR SUMMARY (delta method, q = %.2f) ---\n', FDR_Q);
for oi = 1:numel(outcome_names)
    name = outcome_names{oi};
    mdl  = models.(name);

    full_cov = mdl.CoefficientCovariance;   % (numPC+1) x (numPC+1), row/col 1 = intercept
    Cov_beta = full_cov(2:end, 2:end);      % drop intercept
    df       = mdl.DFE;                     % residual degrees of freedom (shared across all pixels)

    pixel_var = sum((coeff * Cov_beta) .* coeff, 2);   % [n_in_mask x 1]
    pixel_var = max(pixel_var, eps);                    % guard against numerical negatives
    pixel_se  = sqrt(pixel_var);

    pb = pixel_betas.(name);
    t_vals = pb ./ pixel_se;
    p_vals = 2 * (1 - tcdf(abs(t_vals), df));

    [fdr_mask, p_adj] = bh_fdr(p_vals, FDR_Q);

    n_sig = nnz(fdr_mask);
    fprintf('  %-8s : df=%d | significant pixels = %d / %d (%.2f%%)\n', ...
        name, df, n_sig, n_in_mask, 100*n_sig/n_in_mask);

    stats.(name).t        = t_vals;
    stats.(name).p        = p_vals;
    stats.(name).p_adj    = p_adj;
    stats.(name).fdr_mask = fdr_mask;
    stats.(name).df       = df;
end
fprintf('-----------------------------------------------------------\n\n');

% Thresholded (FDR-significant-only) beta maps
fig_fdr = figure;
panel = 1;
for oi = 1:numel(outcome_names)
    name = outcome_names{oi};
    pb_thresh = pixel_betas.(name);
    pb_thresh(~stats.(name).fdr_mask) = NaN;
    img_thresh = make_img(mask, in_mask, pb_thresh);

    subplot(2,2,panel);
    imagesc(img_thresh, [-M M]); axis image off; colormap(hotcoldmap); colorbar;
    title(sprintf('%s (FDR q<%.2f, n=%d)', name, FDR_Q, nnz(stats.(name).fdr_mask)));
    panel = panel + 1;
end
sgtitle(sprintf('FDR-thresholded PCA Regression Maps (Subject-level, N=%d)', n_subj));
saveas(fig_fdr, fullfile(pictures_dir, [cfg.pic_prefix 'regression_maps_subjectlevel_FDR.png']));

%% ── 10c. PC-level coefficient significance (which components matter) ────
% Independent per-PC t-tests already provided by fitlm; FDR-corrected
% across components (numPC tests) per outcome.
fprintf('--- PC-LEVEL COEFFICIENT SIGNIFICANCE (FDR q = %.2f) ---\n', FDR_Q);
pc_stats = struct();
for oi = 1:numel(outcome_names)
    name = outcome_names{oi};
    mdl  = models.(name);
    pc_p = mdl.Coefficients.pValue(2:end);      % drop intercept row
    pc_t = mdl.Coefficients.tStat(2:end);
    [pc_fdr_mask, pc_p_adj] = bh_fdr(pc_p, FDR_Q);

    pc_stats.(name).t        = pc_t;
    pc_stats.(name).p        = pc_p;
    pc_stats.(name).p_adj    = pc_p_adj;
    pc_stats.(name).fdr_mask = pc_fdr_mask;

    sig_pcs = find(pc_fdr_mask)';
    if isempty(sig_pcs)
        fprintf('  %-8s : no PCs survive FDR correction\n', name);
    else
        fprintf('  %-8s : significant PCs = %s\n', name, mat2str(sig_pcs));
    end
end
fprintf('---------------------------------------------------------\n\n');

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
     'stats','pc_stats','FDR_Q', ...
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

function [h, p_adj] = bh_fdr(p, q)
%BH_FDR  Benjamini-Hochberg FDR correction.
%   h     : logical vector, true where the null is rejected at rate q
%   p_adj : BH-adjusted p-values (monotone step-up), same order as p
    p = p(:);
    n = numel(p);
    [sp, idx] = sort(p);

    thresh = (1:n)' / n * q;
    below  = sp <= thresh;
    if any(below)
        max_i = find(below, 1, 'last');
    else
        max_i = 0;
    end

    h = false(n,1);
    if max_i > 0
        h(idx(1:max_i)) = true;
    end

    % Monotone BH-adjusted p-values (step-up)
    adj_sorted = sp .* n ./ (1:n)';
    adj_sorted = min(adj_sorted, 1);
    for i = n-1:-1:1
        adj_sorted(i) = min(adj_sorted(i), adj_sorted(i+1));
    end
    p_adj = nan(n,1);
    p_adj(idx) = adj_sorted;
end