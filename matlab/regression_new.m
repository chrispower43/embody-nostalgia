%% Pixel-level Regression: Bodily Sensation ~ Positive/Negative Feelings
%  (Subject-level, nostalgia trials only)
%
% For each pixel, fits two OLS regressions ACROSS SUBJECTS (one data point
% per subject, not per trial):
%
%   nostalgia_avg_pixel ~ beta0 + beta1 * mean(N1_pos..N4_pos)   (Model 1)
%   nostalgia_avg_pixel ~ beta0 + beta1 * mean(N1_neg..N4_neg)   (Model 2)
%
% Each subject is required to have all 4 nostalgia trials with valid
% (non-blank, non-DATA_EXPIRED) pos/neg ratings, since by study design every
% subject completes exactly 4 nostalgia trials. Subjects failing this check
% are reported and excluded, NOT silently dropped.
%
% Pixel data source: nostalgia_avg field of each subject's .mat file
% (already an average across that subject's valid nostalgia trials).
% Control trials are NOT used anywhere in this script.

clear; clc;

%% ── 0.  Paths ────────────────────────────────────────────────────────────
cfg      = read_config();
data_dir = fullfile(cfg.subjects_dir, 'all', 'unfiltered');
csv_path  = cfg.combined_csv;

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

%% ── 2.  List .mat files ──────────────────────────────────────────────────
fprintf('Scanning .mat files in %s ...\n', data_dir);
mat_files = dir(fullfile(data_dir, '*.mat'));
if isempty(mat_files)
    error('No .mat files found in %s', data_dir);
end

%% ── 3.  Per-subject pass: validate 4/4 nostalgia trials, average ratings ──
n_subj_total   = numel(mat_files);
subj_id        = strings(n_subj_total,1);
subj_pixel     = nan(IMG_H, IMG_W, n_subj_total);
subj_pos_mean  = nan(n_subj_total,1);
subj_neg_mean  = nan(n_subj_total,1);
keep           = false(n_subj_total,1);

n_skipped_nomatch  = 0;
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

    subj_id(f)       = fname;
    subj_pixel(:,:,f)= pix;
    subj_pos_mean(f) = mean(pos_vals);
    subj_neg_mean(f) = mean(neg_vals);
    keep(f)          = true;
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

% Each row here is ONE subject. df = n_subj - 2 downstream, exactly matching
% the number of independent units of information -- no pseudoreplication.

%% ── 4.  Reshape to [n_subj x n_pix] for vectorized regression ────────────
n_pix = IMG_H * IMG_W;
Y = reshape(subj_pixel, n_pix, n_subj)';   % [n_subj x n_pix]

%% ── 5.  OLS per pixel, across subjects ────────────────────────────────────
fprintf('Computing subject-level regressions (N = %d subjects) ...\n', n_subj);
[beta_pos, t_pos, p_pos] = ols_per_pixel(subj_pos_mean, Y);
[beta_neg, t_neg, p_neg] = ols_per_pixel(subj_neg_mean, Y);

beta_pos = reshape(beta_pos, IMG_H, IMG_W);
t_pos    = reshape(t_pos,    IMG_H, IMG_W);
p_pos    = reshape(p_pos,    IMG_H, IMG_W);
beta_neg = reshape(beta_neg, IMG_H, IMG_W);
t_neg    = reshape(t_neg,    IMG_H, IMG_W);
p_neg    = reshape(p_neg,    IMG_H, IMG_W);

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
p_pos_fdr = nan(IMG_H, IMG_W);
p_neg_fdr = nan(IMG_H, IMG_W);
p_pos_fdr(in_mask) = fdr_bh(p_pos(in_mask));
p_neg_fdr(in_mask) = fdr_bh(p_neg(in_mask));

%% ── 8.  Save ─────────────────────────────────────────────────────────────
save('pixel_regression_results_subjectlevel.mat', ...
     'beta_pos','t_pos','p_pos','p_pos_fdr', ...
     'beta_neg','t_neg','p_neg','p_neg_fdr', ...
     'subj_id','n_subj');
fprintf('Results saved to pixel_regression_results_subjectlevel.mat\n');

%% ── 9.  Visualise ─────────────────────────────────────────────────────────
alpha_thresh = 0.05;
cmap = make_hotcold(64);

sig_pos = in_mask & (p_pos_fdr < alpha_thresh);
sig_neg = in_mask & (p_neg_fdr < alpha_thresh);

figure('Name','Pixel Regression Results (Subject-level, Nostalgia only)', ...
       'NumberTitle','off','Color','w','Position',[100 100 1200 800]);

plot_body(subplot(2,3,1), beta_pos, in_mask, cmap, '\beta - Positive Feelings');
plot_body(subplot(2,3,2), t_pos,    in_mask, cmap, 't-stat - Positive Feelings');
plot_body_masked(subplot(2,3,3), beta_pos, in_mask, sig_pos, cmap, ...
                 sprintf('\\beta sig (FDR p<%.2f) - Positive', alpha_thresh));

plot_body(subplot(2,3,4), beta_neg, in_mask, cmap, '\beta - Negative Feelings');
plot_body(subplot(2,3,5), t_neg,    in_mask, cmap, 't-stat - Negative Feelings');
plot_body_masked(subplot(2,3,6), beta_neg, in_mask, sig_neg, cmap, ...
                 sprintf('\\beta sig (FDR p<%.2f) - Negative', alpha_thresh));

sgtitle(sprintf('Bodily Sensation Pixel Regression (Subject-level, N=%d, Nostalgia only)', n_subj));

pictures_dir = fullfile('pictures','regression');
if ~exist(pictures_dir,'dir'), mkdir(pictures_dir); end
saveas(gcf, fullfile(pictures_dir,'pixel_regression_maps_subjectlevel.png'));
fprintf('Saved figure to %s\n', fullfile(pictures_dir,'pixel_regression_maps_subjectlevel.png'));

fprintf('\nSummary (FDR p < %.2f, in-mask pixels only, N=%d subjects):\n', alpha_thresh, n_subj);
fprintf('  Positive: %d / %d significant (%.1f%%)\n', ...
        nnz(sig_pos), n_in_mask, 100*nnz(sig_pos)/n_in_mask);
fprintf('  Negative: %d / %d significant (%.1f%%)\n', ...
        nnz(sig_neg), n_in_mask, 100*nnz(sig_neg)/n_in_mask);


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

function [beta1, tstat, pval] = ols_per_pixel(x, Y)
% Vectorized simple linear regression y_pix = b0 + b1*x across subjects,
% fit independently for every pixel (column of Y).
%   x : [n_subj x 1]   predictor (e.g. mean pos rating per subject)
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