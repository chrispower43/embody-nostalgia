%% Pixel-level Regression: Bodily Sensation ~ Trait Measures (SNS / BMRQ / SES)
%  (Subject-level, nostalgia trials only)
%
% For each pixel, fits three OLS regressions ACROSS SUBJECTS (one data point
% per subject, not per trial):
%
%   nostalgia_avg_pixel ~ beta0 + beta1 * SNS_score           (Model 1)
%   nostalgia_avg_pixel ~ beta0 + beta1 * BMRQ_score          (Model 2)
%   nostalgia_avg_pixel ~ beta0 + beta1 * SES_country_score   (Model 3)
%
% Unlike the pos/neg/min regression, these predictors are subject-level
% TRAIT measures (Southampton Nostalgia Scale, Barcelona Music Reward
% Questionnaire, subjective socioeconomic status), not per-trial ratings
% averaged across trials. There is therefore no "4/4 valid nostalgia trial"
% check to perform here -- instead, a subject is included in a given model
% only if that subject has a non-missing score for that trait (this already
% respects the SES_country_flag: an all-OFF SES ladder yields SES_country_score
% = NaN and is excluded, logged below like any other missing value).
%
% Pixel data source: nostalgia_avg field of each subject's .mat file
% (already an average across that subject's valid nostalgia trials).
% Control trials are NOT used anywhere in this script.

clear; clc;

%% ── 0.  Paths ────────────────────────────────────────────────────────────
cfg      = read_config();
data_dir = fullfile(cfg.subjects_dir, 'all', 'unfiltered');
csv_path  = cfg.combined_csv;
pictures_dir = fullfile(cfg.exploratory);

IMG_H = 522;
IMG_W = 171;

%% ── 1.  Load survey CSV ──────────────────────────────────────────────────
fprintf('Loading survey data from %s ...\n', csv_path);
opts = detectImportOptions(csv_path, 'TextType', 'string', ...
                           'VariableNamingRule', 'preserve');
survey = readtable(csv_path, opts);

ids  = string(survey.('ID'));
pids = string(survey.('PROLIFIC_PID'));

id_map  = containers.Map(ids,  num2cell(1:height(survey)));
pid_map = containers.Map(pids, num2cell(1:height(survey)));

TRAIT_COLS = {'SNS_score', 'BMRQ_score', 'SES_country_score'};
for t = 1:numel(TRAIT_COLS)
    if ~ismember(TRAIT_COLS{t}, survey.Properties.VariableNames)
        error('Expected column "%s" not found in %s. Re-run build_combined_data.py first.', ...
              TRAIT_COLS{t}, csv_path);
    end
end

%% ── 2.  List .mat files ──────────────────────────────────────────────────
fprintf('Scanning .mat files in %s ...\n', data_dir);
mat_files = dir(fullfile(data_dir, '*.mat'));
if isempty(mat_files)
    error('No .mat files found in %s', data_dir);
end

%% ── 3.  Per-subject pass: match to CSV, pull pixel map + trait scores ─────
n_subj_total  = numel(mat_files);
subj_id       = strings(n_subj_total,1);
subj_pixel    = nan(IMG_H, IMG_W, n_subj_total);
subj_sns      = nan(n_subj_total,1);
subj_bmrq     = nan(n_subj_total,1);
subj_ses      = nan(n_subj_total,1);
keep          = false(n_subj_total,1);

n_skipped_nomatch = 0;
n_skipped_nofield  = 0;

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

    subj_id(f)        = fname;
    subj_pixel(:,:,f) = pix;
    subj_sns(f)       = read_trait(survey, 'SNS_score', row);
    subj_bmrq(f)      = read_trait(survey, 'BMRQ_score', row);
    subj_ses(f)        = read_trait(survey, 'SES_country_score', row);
    keep(f)           = true;
end

fprintf('\n--- SUBJECT MATCHING SUMMARY ---\n');
fprintf('Total .mat files scanned        : %d\n', n_subj_total);
fprintf('Skipped (no CSV match)          : %d\n', n_skipped_nomatch);
fprintf('Skipped (missing nostalgia_avg) : %d\n', n_skipped_nofield);
fprintf('Matched subjects                : %d\n', nnz(keep));
fprintf('----------------------------------\n\n');

subj_id    = subj_id(keep);
subj_pixel = subj_pixel(:,:,keep);
subj_sns   = subj_sns(keep);
subj_bmrq  = subj_bmrq(keep);
subj_ses   = subj_ses(keep);

% Each trait model uses only the subjects with a non-missing score for that
% specific trait; log who gets dropped and why, per model.
[subj_sns_valid,  idx_sns]  = drop_missing(subj_sns,  subj_id, 'SNS_score');
[subj_bmrq_valid, idx_bmrq] = drop_missing(subj_bmrq, subj_id, 'BMRQ_score');
[subj_ses_valid,  idx_ses]  = drop_missing(subj_ses,  subj_id, 'SES_country_score');

if isempty(subj_sns_valid) || isempty(subj_bmrq_valid) || isempty(subj_ses_valid)
    error('One or more trait predictors has zero valid subjects. Check combined_data_all.csv.');
end

%% ── 4.  Reshape to [n_subj x n_pix] for vectorized regression ────────────
n_pix = IMG_H * IMG_W;

Y_all = reshape(subj_pixel, n_pix, size(subj_pixel,3))';   % [n_subj_total_matched x n_pix]

Y_sns  = Y_all(idx_sns,  :);
Y_bmrq = Y_all(idx_bmrq, :);
Y_ses  = Y_all(idx_ses,  :);

%% ── 5.  OLS per pixel, across subjects ────────────────────────────────────
fprintf('Computing subject-level regressions ...\n');
fprintf('  SNS model  : N = %d subjects\n', numel(subj_sns_valid));
fprintf('  BMRQ model : N = %d subjects\n', numel(subj_bmrq_valid));
fprintf('  SES model  : N = %d subjects\n', numel(subj_ses_valid));

[beta_sns,  t_sns,  p_sns]  = ols_per_pixel(subj_sns_valid,  Y_sns);
[beta_bmrq, t_bmrq, p_bmrq] = ols_per_pixel(subj_bmrq_valid, Y_bmrq);
[beta_ses,  t_ses,  p_ses]  = ols_per_pixel(subj_ses_valid,  Y_ses);

beta_sns  = reshape(beta_sns,  IMG_H, IMG_W);
t_sns     = reshape(t_sns,     IMG_H, IMG_W);
p_sns     = reshape(p_sns,     IMG_H, IMG_W);
beta_bmrq = reshape(beta_bmrq, IMG_H, IMG_W);
t_bmrq    = reshape(t_bmrq,    IMG_H, IMG_W);
p_bmrq    = reshape(p_bmrq,    IMG_H, IMG_W);
beta_ses  = reshape(beta_ses,  IMG_H, IMG_W);
t_ses     = reshape(t_ses,     IMG_H, IMG_W);
p_ses     = reshape(p_ses,     IMG_H, IMG_W);

%% ── 6.  Load body mask ────────────────────────────────────────────────────
mask_path = 'mask.png';
if exist(mask_path, 'file')
    mask = imread(mask_path);
    if ndims(mask) == 3, mask = mask(:,:,1); end
    if ~isequal(size(mask), [IMG_H, IMG_W])
        warning('mask size %s differs from data %dx%d; attempting resize.', ...
                mat2str(size(mask)), IMG_H, IMG_W);
        try
            mask = imresize(mask, [IMG_H, IMG_W]);
        catch
            warning('Could not resize mask; plotting full frame.');
            mask = 255*ones(IMG_H, IMG_W, 'uint8');
        end
    end
    in_mask = mask > 128;
else
    warning('mask.png not found - plotting full frame without silhouette.');
    in_mask = true(IMG_H, IMG_W);
end
n_in_mask = nnz(in_mask);
fprintf('Pixels inside mask: %d / %d\n', n_in_mask, n_pix);

%% ── 7.  FDR correction (Benjamini–Hochberg), restricted to in-mask pixels ─
p_sns_fdr  = nan(IMG_H, IMG_W);
p_bmrq_fdr = nan(IMG_H, IMG_W);
p_ses_fdr  = nan(IMG_H, IMG_W);
p_sns_fdr(in_mask)  = fdr_bh(p_sns(in_mask));
p_bmrq_fdr(in_mask) = fdr_bh(p_bmrq(in_mask));
p_ses_fdr(in_mask)  = fdr_bh(p_ses(in_mask));

%% ── 8.  Save ─────────────────────────────────────────────────────────────
save('pixel_regression_results_traits_subjectlevel.mat', ...
     'beta_sns','t_sns','p_sns','p_sns_fdr', ...
     'beta_bmrq','t_bmrq','p_bmrq','p_bmrq_fdr', ...
     'beta_ses','t_ses','p_ses','p_ses_fdr', ...
     'subj_id');
fprintf('Results saved to pixel_regression_results_traits_subjectlevel.mat\n');

%% ── 9.  Visualise ─────────────────────────────────────────────────────────
alpha_thresh = 0.05;
cmap = make_hotcold(64);

sig_sns  = in_mask & (p_sns_fdr  < alpha_thresh);
sig_bmrq = in_mask & (p_bmrq_fdr < alpha_thresh);
sig_ses  = in_mask & (p_ses_fdr  < alpha_thresh);

figure('Name','Pixel Regression Results (Trait measures, Subject-level)', ...
       'NumberTitle','off','Color','w','Position',[100 100 1800 900]);

plot_body(subplot(3,4,1), beta_sns, in_mask, cmap, '\beta - SNS');
plot_body(subplot(3,4,2), t_sns,    in_mask, cmap, 't-stat - SNS');
plot_body_masked(subplot(3,4,3), t_sns, in_mask, sig_sns, cmap, ...
                 sprintf('t sig (FDR p<%.2f) - SNS', alpha_thresh));
plot_body_masked(subplot(3,4,4), beta_sns, in_mask, sig_sns, cmap, ...
                 sprintf('\\beta sig (FDR p<%.2f) - SNS', alpha_thresh));

plot_body(subplot(3,4,5), beta_bmrq, in_mask, cmap, '\beta - BMRQ');
plot_body(subplot(3,4,6), t_bmrq,    in_mask, cmap, 't-stat - BMRQ');
plot_body_masked(subplot(3,4,7), t_bmrq, in_mask, sig_bmrq, cmap, ...
                 sprintf('t sig (FDR p<%.2f) - BMRQ', alpha_thresh));
plot_body_masked(subplot(3,4,8), beta_bmrq, in_mask, sig_bmrq, cmap, ...
                 sprintf('\\beta sig (FDR p<%.2f) - BMRQ', alpha_thresh));

plot_body(subplot(3,4,9),  beta_ses, in_mask, cmap, '\beta - SES (country)');
plot_body(subplot(3,4,10), t_ses,    in_mask, cmap, 't-stat - SES (country)');
plot_body_masked(subplot(3,4,11), t_ses, in_mask, sig_ses, cmap, ...
                 sprintf('t sig (FDR p<%.2f) - SES (country)', alpha_thresh));
plot_body_masked(subplot(3,4,12), beta_ses, in_mask, sig_ses, cmap, ...
                 sprintf('\\beta sig (FDR p<%.2f) - SES (country)', alpha_thresh));

sgtitle('Bodily Sensation Pixel Regression (Trait measures, Subject-level, Nostalgia only)');

if ~exist(pictures_dir,'dir'), mkdir(pictures_dir); end
saveas(gcf, fullfile(pictures_dir,'pixel_regression_maps_traits_subjectlevel.png'));
fprintf('Saved figure to %s\n', fullfile(pictures_dir,'pixel_regression_maps_traits_subjectlevel.png'));

fprintf('\nSummary (FDR p < %.2f, in-mask pixels only):\n', alpha_thresh);
fprintf('  SNS : %d / %d significant (%.1f%%), N=%d\n', ...
        nnz(sig_sns), n_in_mask, 100*nnz(sig_sns)/n_in_mask, numel(subj_sns_valid));
fprintf('  BMRQ: %d / %d significant (%.1f%%), N=%d\n', ...
        nnz(sig_bmrq), n_in_mask, 100*nnz(sig_bmrq)/n_in_mask, numel(subj_bmrq_valid));
fprintf('  SES : %d / %d significant (%.1f%%), N=%d\n', ...
        nnz(sig_ses), n_in_mask, 100*nnz(sig_ses)/n_in_mask, numel(subj_ses_valid));


%% ═══════════════════════════════════════════════════════════════════════
%  LOCAL FUNCTIONS
%% ═══════════════════════════════════════════════════════════════════════

function v = read_trait(survey, colname, row)
% Returns a numeric trait score, or NaN if missing/blank.
    raw = survey.(colname)(row);
    if iscell(raw), raw = raw{1}; end
    if isstring(raw) || ischar(raw)
        s = string(raw);
        if s=="" || s=="DATA_EXPIRED", v = NaN; return; end
        v = str2double(s);
    else
        v = double(raw);
    end
end

function [vals_valid, idx_valid] = drop_missing(vals, subj_id, label)
% Logs and drops subjects with a missing (NaN) score for a given trait.
    idx_valid  = find(~isnan(vals));
    idx_missing = find(isnan(vals));
    if ~isempty(idx_missing)
        fprintf('[DEBUG] %s: excluding %d subject(s) with missing score:\n', label, numel(idx_missing));
        for i = 1:numel(idx_missing)
            fprintf('    %s\n', subj_id(idx_missing(i)));
        end
    end
    vals_valid = vals(idx_valid);
end

function [beta1, tstat, pval] = ols_per_pixel(x, Y)
% Vectorized simple linear regression y_pix = b0 + b1*x across subjects,
% fit independently for every pixel (column of Y).
%   x : [n_subj x 1]   predictor (e.g. subject's trait score)
%   Y : [n_subj x n_pix] response (subject-averaged pixel values)
    n = size(Y,1);
    xc = x - mean(x);
    Sxx = sum(xc.^2);

    Yc = Y - mean(Y,1);
    Sxy = xc' * Yc;                 % [1 x n_pix]
    beta1 = (Sxy / Sxx)';           % [n_pix x 1]

    Yhat_resid = Yc - xc * (Sxy / Sxx);   % residuals after removing fit
    SSres = sum(Yhat_resid.^2, 1)';       % [n_pix x 1]

    df = n - 2;
    s2 = SSres / max(df,1);
    var_b1 = s2 / Sxx;

    tstat = beta1 ./ sqrt(var_b1);
    pval  = 2 * (1 - tcdf(abs(tstat), max(df,1)));

    if df < 1
        tstat(:) = 0;
        pval(:)  = 1;
    end
end

function p_adj = fdr_bh(p_vals)
% Benjamini-Hochberg FDR correction.
    p_vals = p_vals(:);
    m = numel(p_vals);
    [p_sorted, sort_idx] = sort(p_vals);
    p_bh = p_sorted .* m ./ (1:m)';
    for i = m-1:-1:1
        p_bh(i) = min(p_bh(i), p_bh(i+1));
    end
    p_bh = min(p_bh, 1);
    p_adj = zeros(m,1);
    p_adj(sort_idx) = p_bh;
end

function cmap = make_hotcold(numcol)
    if nargin < 1, numcol = 64; end
    hotmap  = hot(numcol);
    coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
    cmap    = [coldmap; hotmap];
end

function M = robust_M(vals)
    v = vals(:);
    v = v(~isnan(v) & v ~= 0);
    if isempty(v), M = 1; return; end
    M = prctile(abs(v), 99);
    if M <= 0 || isnan(M), M = max(abs(v)) + eps; end
end

function plot_body(ax, map2d, in_mask, cmap, ttl)
    img = nan(size(map2d));
    img(in_mask) = map2d(in_mask);
    M = robust_M(img(in_mask));
    imagesc(ax, img, [-M M]);
    set(ax, 'Color', 'w');
    axis(ax, 'image'); axis(ax, 'off');
    colormap(ax, cmap); colorbar(ax);
    title(ax, ttl);
end

function plot_body_masked(ax, beta2d, in_mask, sig_mask, cmap, ttl)
    img = nan(size(beta2d));
    img(in_mask)  = 0;
    img(sig_mask) = beta2d(sig_mask);
    if any(sig_mask(:))
        M = robust_M(beta2d(sig_mask));
    else
        M = robust_M(beta2d(in_mask));
    end
    imagesc(ax, img, [-M M]);
    set(ax, 'Color', 'w');
    axis(ax, 'image'); axis(ax, 'off');
    colormap(ax, cmap); colorbar(ax);
    title(ax, ttl);
end