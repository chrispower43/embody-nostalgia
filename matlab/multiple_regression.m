%% Pixel-level MULTIVARIABLE Regression: Bodily Sensation ~ Pos + Neg (jointly)
%  (Subject-level, nostalgia trials only)
%
% Unlike the univariate script (three SEPARATE simple regressions, one per
% predictor), this fits ONE multiple regression per pixel with BOTH
% predictors entered simultaneously:
%
%   nostalgia_avg_pixel ~ beta0 + beta1*mean(pos) + beta2*mean(neg)
%
% beta1 is therefore the effect of positive feelings HOLDING NEGATIVE
% FEELINGS CONSTANT (and vice versa for beta2) -- the unique contribution
% of each predictor after partialling out the other. This differs from the
% univariate maps whenever pos and neg are correlated across subjects.
%
% Each subject is required to have all 4 nostalgia trials with valid
% (non-blank, non-DATA_EXPIRED) pos/neg ratings, since by study design every
% subject completes exactly 4 nostalgia trials. Subjects failing this check
% are reported and excluded, NOT silently dropped.
%
% Pixel data source: nostalgia_avg field of each subject's .mat file
% (already an average across that subject's valid nostalgia trials).
% Control trials are NOT used anywhere in this script.
%
% IMPLEMENTATION NOTE: because every pixel shares the SAME design matrix
% X = [1, pos, neg] (only the response Y changes per pixel), the whole
% mass-univariate GLM is solved as one matrix multiply
% B = (X'X)^-1 X' Y  rather than looping fitlm() ~50,000 times.

clear; clc;

%% ── 0.  Paths ────────────────────────────────────────────────────────────
cfg      = read_config();
data_dir = fullfile(cfg.subjects_dir, 'all', 'unfiltered');
csv_path  = cfg.combined_csv;
pictures_dir = cfg.multi_regression;

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
subj_min_mean  = nan(n_subj_total,1);
keep           = false(n_subj_total,1);

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
    subj_min_mean(f)  = min(mean(pos_vals), mean(neg_vals));
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

% Report collinearity between predictors -- the more correlated they are,
% the more the multivariable betas will diverge from the univariate ones,
% and the less stable/interpretable the "unique contribution" split becomes.
% Note min(pos,neg) is a NONLINEAR function of pos and neg, so it is not
% redundant with them in a linear design matrix even though it is derived
% from them -- but it is still worth checking how strongly it tracks each
% one linearly, since large min/neg correlation (say) is expected whenever
% neg tends to be the smaller of the two.
r_pos_neg = corr(subj_pos_mean, subj_neg_mean);
r_pos_min = corr(subj_pos_mean, subj_min_mean);
r_neg_min = corr(subj_neg_mean, subj_min_mean);
fprintf('corr(pos, neg) = %.3f | corr(pos, min) = %.3f | corr(neg, min) = %.3f\n', ...
        r_pos_neg, r_pos_min, r_neg_min);
if abs(r_pos_neg) > 0.7
    warning(['pos and neg are highly correlated (r=%.2f) across subjects. ', ...
             'Multivariable beta estimates may be unstable -- interpret with caution.'], r_pos_neg);
end
if max(abs(r_pos_min), abs(r_neg_min)) > 0.85
    warning(['min(pos,neg) is very highly correlated with pos or neg (max |r|=%.2f). ', ...
             'Its unique-variance beta may be poorly estimated -- interpret with caution.'], ...
             max(abs(r_pos_min), abs(r_neg_min)));
end

% Each row here is ONE subject. df = n_subj - 4 downstream (intercept + 3
% predictors), exactly matching the number of independent units of
% information -- no pseudoreplication.

%% ── 4.  Reshape to [n_subj x n_pix] for vectorized regression ────────────
n_pix = IMG_H * IMG_W;
Y = reshape(subj_pixel, n_pix, n_subj)';   % [n_subj x n_pix]

%% ── 5.  Multivariable OLS per pixel: Y ~ 1 + pos + neg + min(pos,neg) ────
fprintf('Computing multivariable regressions (N = %d subjects) ...\n', n_subj);
X = [ones(n_subj,1), subj_pos_mean, subj_neg_mean, subj_min_mean];   % shared design matrix
predictor_names = {'intercept','pos','neg','min'};

[B, T, P, df, R2] = ols_multivariable(X, Y);
% B, T, P are [4 x n_pix]: rows = intercept, pos, neg, min

beta_pos = reshape(B(2,:), IMG_H, IMG_W);
t_pos    = reshape(T(2,:), IMG_H, IMG_W);
p_pos    = reshape(P(2,:), IMG_H, IMG_W);

beta_neg = reshape(B(3,:), IMG_H, IMG_W);
t_neg    = reshape(T(3,:), IMG_H, IMG_W);
p_neg    = reshape(P(3,:), IMG_H, IMG_W);

beta_min = reshape(B(4,:), IMG_H, IMG_W);
t_min    = reshape(T(4,:), IMG_H, IMG_W);
p_min    = reshape(P(4,:), IMG_H, IMG_W);

R2_map   = reshape(R2, IMG_H, IMG_W);

fprintf('df = %d (N=%d subjects - 4 params)\n', df, n_subj);

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
% Each predictor is corrected separately across the in-mask pixels tested
% for that predictor (standard practice: one family of tests per contrast).
p_pos_fdr = nan(IMG_H, IMG_W);
p_neg_fdr = nan(IMG_H, IMG_W);
p_min_fdr = nan(IMG_H, IMG_W);
p_pos_fdr(in_mask) = fdr_bh(p_pos(in_mask));
p_neg_fdr(in_mask) = fdr_bh(p_neg(in_mask));
p_min_fdr(in_mask) = fdr_bh(p_min(in_mask));

%% ── 8.  Save ─────────────────────────────────────────────────────────────
save('pixel_multivariable_regression_results_subjectlevel.mat', ...
     'beta_pos','t_pos','p_pos','p_pos_fdr', ...
     'beta_neg','t_neg','p_neg','p_neg_fdr', ...
     'beta_min','t_min','p_min','p_min_fdr', ...
     'R2_map','df','r_pos_neg','r_pos_min','r_neg_min','predictor_names', ...
     'subj_id','n_subj');
fprintf('Results saved to pixel_multivariable_regression_results_subjectlevel.mat\n');

%% ── 9.  Visualise ─────────────────────────────────────────────────────────
alpha_thresh = 0.05;
cmap = make_hotcold(64);

sig_pos = in_mask & (p_pos_fdr < alpha_thresh);
sig_neg = in_mask & (p_neg_fdr < alpha_thresh);
sig_min = in_mask & (p_min_fdr < alpha_thresh);

figure('Name','Pixel Multivariable Regression Results (Subject-level, Nostalgia only)', ...
       'NumberTitle','off','Color','w','Position',[100 100 1800 900]);

plot_body(subplot(3,4,1), beta_pos, in_mask, cmap, '\beta_{pos} (controlling for neg, min)');
plot_body(subplot(3,4,2), t_pos,    in_mask, cmap, 't-stat - Positive | Negative, Min');
plot_body_masked(subplot(3,4,3), t_pos, in_mask, sig_pos, cmap, ...
                 sprintf('t sig (FDR p<%.2f) - Positive', alpha_thresh));
plot_body_masked(subplot(3,4,4), beta_pos, in_mask, sig_pos, cmap, ...
                 sprintf('\\beta_{pos} sig (FDR p<%.2f)', alpha_thresh));

plot_body(subplot(3,4,5), beta_neg, in_mask, cmap, '\beta_{neg} (controlling for pos, min)');
plot_body(subplot(3,4,6), t_neg,    in_mask, cmap, 't-stat - Negative | Positive, Min');
plot_body_masked(subplot(3,4,7), t_neg, in_mask, sig_neg, cmap, ...
                 sprintf('t sig (FDR p<%.2f) - Negative', alpha_thresh));
plot_body_masked(subplot(3,4,8), beta_neg, in_mask, sig_neg, cmap, ...
                 sprintf('\\beta_{neg} sig (FDR p<%.2f)', alpha_thresh));

plot_body(subplot(3,4,9),  beta_min, in_mask, cmap, '\beta_{min} (controlling for pos, neg)');
plot_body(subplot(3,4,10), t_min,    in_mask, cmap, 't-stat - Min | Positive, Negative');
plot_body_masked(subplot(3,4,11), t_min, in_mask, sig_min, cmap, ...
                 sprintf('t sig (FDR p<%.2f) - Min', alpha_thresh));
plot_body_masked(subplot(3,4,12), beta_min, in_mask, sig_min, cmap, ...
                 sprintf('\\beta_{min} sig (FDR p<%.2f)', alpha_thresh));

sgtitle(sprintf(['Multivariable Bodily Sensation Regression (pixel ~ pos + neg + min jointly), ' ...
                  'Subject-level, N=%d, Nostalgia only (r_{pos,neg}=%.2f, r_{pos,min}=%.2f, r_{neg,min}=%.2f)'], ...
                  n_subj, r_pos_neg, r_pos_min, r_neg_min));

if ~exist(pictures_dir,'dir'), mkdir(pictures_dir); end
saveas(gcf, fullfile(pictures_dir,'pixel_multivariable_regression_maps_subjectlevel.png'));
fprintf('Saved figure to %s\n', fullfile(pictures_dir,'pixel_multivariable_regression_maps_subjectlevel.png'));

fprintf('\nSummary (FDR p < %.2f, in-mask pixels only, N=%d subjects, df=%d):\n', ...
        alpha_thresh, n_subj, df);
fprintf('  Positive | Negative: %d / %d significant (%.1f%%)\n', ...
        nnz(sig_pos), n_in_mask, 100*nnz(sig_pos)/n_in_mask);
fprintf('  Negative | Positive: %d / %d significant (%.1f%%)\n', ...
        nnz(sig_neg), n_in_mask, 100*nnz(sig_neg)/n_in_mask);
fprintf('  Min(Pos,Neg) | Positive, Negative: %d / %d significant (%.1f%%)\n', ...
        nnz(sig_min), n_in_mask, 100*nnz(sig_min)/n_in_mask);
fprintf('  Median R^2 (in-mask): %.3f\n', median(R2_map(in_mask), 'omitnan'));


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

function [B, T, P, df, R2] = ols_multivariable(X, Y)
% Vectorized multiple regression, ONE shared design matrix X fit
% independently against every column (pixel) of Y.
%   X : [n_subj x n_pred]   design matrix (first column should be ones)
%   Y : [n_subj x n_pix]    response (subject-averaged pixel values)
%
%   B  : [n_pred x n_pix]  coefficient estimates
%   T  : [n_pred x n_pix]  t-statistics
%   P  : [n_pred x n_pix]  two-sided p-values
%   df : scalar            residual degrees of freedom (shared, since X
%                           is shared across all pixels)
%   R2 : [n_pix x 1]        R^2 per pixel
    [n, k] = size(X);
    df = n - k;
    if df < 1
        error('ols_multivariable:insufficientDF', ...
              'Not enough subjects (N=%d) for %d predictors + intercept.', n, k);
    end

    XtX     = X' * X;                 % [k x k]
    XtX_inv = XtX \ eye(k);           % avoid explicit inv() where possible
    Beta    = XtX_inv * (X' * Y);     % [k x n_pix]  -- normal equations, solved once

    Yhat  = X * Beta;                 % [n x n_pix]
    resid = Y - Yhat;
    SSres = sum(resid.^2, 1);         % [1 x n_pix]
    Ybar  = mean(Y, 1);
    SStot = sum((Y - Ybar).^2, 1);    % [1 x n_pix]
    SStot(SStot == 0) = eps;          % guard against constant pixels
    R2    = (1 - SSres ./ SStot)';    % [n_pix x 1]

    sigma2 = SSres / df;              % [1 x n_pix]
    se_scale = sqrt(diag(XtX_inv));   % [k x 1], same for every pixel
    SE = se_scale * sqrt(sigma2);     % [k x n_pix], outer product broadcast

    B = Beta;
    T = B ./ SE;
    P = 2 * (1 - tcdf(abs(T), df));
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