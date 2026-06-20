%% Pixel-level MULTIPLE Regression: Bodily Sensation ~ Positive + Negative + Minimum
%
% For each pixel, fits ONE multiple OLS regression across all trials
% (pooled across subjects and song conditions):
%
%   pixel_value ~ b0 + b1*pos + b2*neg + b3*min(pos,neg)
%
% Unlike the earlier valence script (which fit two SEPARATE simple
% regressions), every slope here is a PARTIAL effect: b1 is the effect of
% positive feeling holding negative and the ambivalence index fixed, etc.
%
% "Minimum" is the ambivalence / mixed-feeling index:
%       min_values = min(pos_values, neg_values);
%
% Because all three predictors enter one model, a trial contributes only
% if BOTH pos and neg are present (listwise deletion). A trial missing
% either rating is dropped entirely rather than per-model.
%
% Implementation note: the three predictors are scalars per trial (constant
% across pixels), so the design matrix is identical for every pixel. We
% therefore accumulate ONE 4x4 X'X for the whole dataset and a 4 x n_pix
% X'y, then solve all pixels at once:  B = (X'X)\(X'y).
%
% Uses unfiltered .mat files from final&new_subjects/all/unfiltered/
% and survey ratings from combined_data_all.csv.
%
% Outputs (each [522 x 171])
% --------------------------
%   beta_pos / beta_neg / beta_min   partial slope maps
%   beta_int                         intercept map
%   t_pos / t_neg / t_min            partial t-statistic maps
%   p_pos / p_neg / p_min            two-tailed p-value maps
%   p_pos_fdr / p_neg_fdr / p_min_fdr  BH-FDR-corrected p-value maps

clear; clc;

%% -- 0.  Paths -----------------------------------------------------------
data_dir = fullfile('final&new_subjects', 'all', 'unfiltered');
csv_path = 'combined_data_all.csv';

% Create / clean output folder  (prefix keeps cohorts separate)
output_folder = cfg.pic_pq0;

IMG_H = 522;
IMG_W = 171;
n_pix = IMG_H * IMG_W;
P     = 4;            % # parameters: intercept, pos, neg, min

%% -- 1.  Load survey CSV -------------------------------------------------
fprintf('Loading survey data from %s ...\n', csv_path);
opts   = detectImportOptions(csv_path, 'TextType', 'string', ...
                             'VariableNamingRule', 'preserve');
survey = readtable(csv_path, opts);

% Build lookup maps for BOTH possible filename keys
id_map  = containers.Map('KeyType','char','ValueType','double');
pid_map = containers.Map('KeyType','char','ValueType','double');
for r = 1:height(survey)
    id_map(char(string(survey.ID(r))))           = r;
    pid_map(char(string(survey.PROLIFIC_PID(r)))) = r;
end

%% -- 2.  Trial column prefixes and mat-field mapping --------------------
trial_prefixes = {'N1','N2','N3','N4','C1','C2','C3','C4'};
prefix2field = containers.Map( ...
    {'N1','N2','N3','N4','C1','C2','C3','C4'}, ...
    {'Nost1','Nost2','Nost3','Nost4','Cont1','Cont2','Cont3','Cont4'});

%% -- 3.  Accumulate sufficient statistics --------------------------------
% XtX : 4x4   (same for every pixel)
% Xty : 4 x n_pix
% syy : 1 x n_pix   (sum of y^2 per pixel, for residual variance)
fprintf('Scanning unfiltered .mat files in %s ...\n', data_dir);
mat_files = dir(fullfile(data_dir, '*.mat'));
if isempty(mat_files)
    error('No .mat files found in %s', data_dir);
end

XtX = zeros(P, P);
Xty = zeros(P, n_pix);
syy = zeros(1, n_pix);
n_obs           = 0;
n_skipped_files = 0;
n_trials_loaded = 0;

% --- one-time diagnostic so a 0-match run is debuggable -----------------
fprintf('\n--- key sample (first 3) ---\n');
fprintf('CSV ID  : %s\n', strjoin(cellstr(string(survey.ID(1:min(3,end)))), ', '));
fprintf('CSV PID : %s\n', strjoin(cellstr(string(survey.PROLIFIC_PID(1:min(3,end)))), ', '));
fprintf('files   : %s\n\n', strjoin({mat_files(1:min(3,end)).name}, ', '));

for f = 1:numel(mat_files)
    fname = mat_files(f).name;
    row   = lookup_row(fname, id_map, pid_map);
    if isnan(row)
        n_skipped_files = n_skipped_files + 1;
        continue
    end

    S = load(fullfile(data_dir, fname));

    for t = 1:numel(trial_prefixes)
        pre   = trial_prefixes{t};
        field = prefix2field(pre);
        if ~isfield(S, field), continue; end

        pos = read_rating(survey.(sprintf('%s_pos', pre))(row));
        neg = read_rating(survey.(sprintf('%s_neg', pre))(row));

        % listwise deletion: need both pos and neg for min + full model
        if isnan(pos) || isnan(neg), continue; end
        mn = min(pos, neg);

        y = double(S.(field)(:))';        % 1 x n_pix
        if numel(y) ~= n_pix
            warning('Skipping %s/%s: %d pixels (expected %d).', ...
                     fname, field, numel(y), n_pix);
            continue
        end

        x = [1; pos; neg; mn];            % 4 x 1
        XtX = XtX + (x * x');             % 4 x 4
        Xty = Xty + (x * y);             % 4 x n_pix
        syy = syy + y.^2;                 % 1 x n_pix
        n_obs           = n_obs + 1;
        n_trials_loaded = n_trials_loaded + 1;
    end

    if mod(f, 50) == 0
        fprintf('  ...processed %d / %d files\n', f, numel(mat_files));
    end
end

fprintf('\nTrials loaded: %d  |  files with no CSV match: %d\n', ...
        n_trials_loaded, n_skipped_files);
if n_obs < P
    error('Only %d usable trials (< %d params). Check ID matching above.', n_obs, P);
end

%% -- 4.  Predictor collinearity diagnostic ------------------------------
% min(pos,neg) is a deterministic (piecewise-linear) function of pos & neg,
% so it WILL correlate with both. The model is still identified (min is not
% a linear combination of pos, neg, 1), but partial slopes can be unstable
% if correlations are extreme. Inspect before trusting individual betas.
mu_x  = XtX(1, 2:4) / n_obs;                 % means of [pos neg min]
Exx   = XtX(2:4, 2:4) / n_obs;
covx  = Exx - (mu_x' * mu_x);
sdx   = sqrt(diag(covx));
corrx = covx ./ (sdx * sdx');
fprintf('\nPredictor correlation matrix [pos neg min]:\n');
disp(corrx);
fprintf('cond(X''X) = %.3g   (large => multicollinearity)\n\n', cond(XtX));

%% -- 5.  Solve all pixels at once ----------------------------------------
fprintf('Fitting multiple regression for %d pixels ...\n', n_pix);
C = inv(XtX);                 % 4 x 4 ; C(k,k) scales coeff variance
B = C * Xty;                  % 4 x n_pix : rows = [int; pos; neg; min]

% Residual sum of squares per pixel: SSE = y'y - beta' X'y
SSE   = syy - sum(B .* Xty, 1);     % 1 x n_pix
SSE   = max(SSE, 0);                % guard tiny negatives from roundoff
df    = n_obs - P;
sig2  = SSE / df;                   % 1 x n_pix residual variance

% Standard errors & t-stats per coefficient: SE_k = sqrt(sig2 * C(k,k))
se    = sqrt(diag(C) * sig2);       % 4 x n_pix
Tstat = B ./ se;                    % 4 x n_pix
Pval  = 2 * tcdf(-abs(Tstat), df);  % 4 x n_pix two-tailed

%% -- 6.  Reshape coefficient maps ---------------------------------------
rs = @(v) reshape(v, IMG_H, IMG_W);

beta_int = rs(B(1,:));
beta_pos = rs(B(2,:));   t_pos = rs(Tstat(2,:));   p_pos = rs(Pval(2,:));
beta_neg = rs(B(3,:));   t_neg = rs(Tstat(3,:));   p_neg = rs(Pval(3,:));
beta_min = rs(B(4,:));   t_min = rs(Tstat(4,:));   p_min = rs(Pval(4,:));

%% -- 7.  FDR correction (Benjamini-Hochberg), per coefficient map --------
p_pos_fdr = rs(fdr_bh(p_pos(:)));
p_neg_fdr = rs(fdr_bh(p_neg(:)));
p_min_fdr = rs(fdr_bh(p_min(:)));

%% -- 8.  Save -----------------------------------------------------------
out_file = 'pixel_multiple_regression_results.mat';
save(out_file, ...
     'beta_int', ...
     'beta_pos','t_pos','p_pos','p_pos_fdr', ...
     'beta_neg','t_neg','p_neg','p_neg_fdr', ...
     'beta_min','t_min','p_min','p_min_fdr', ...
     'n_obs','df','corrx');
fprintf('Saved results to %s  (n=%d trials, df=%d)\n', out_file, n_obs, df);

%% -- 9.  Quick visualisation --------------------------------------------
base = []; try, base = imread('base.png'); catch, end %#ok<NASGU>
maps = {beta_pos, beta_neg, beta_min};
ttls = {'\beta Positive', '\beta Negative', '\beta Minimum (ambivalence)'};
figure('Color','w','Name','Partial slope maps');
for k = 1:3
    subplot(1,3,k);
    m  = maps{k};
    lim = max(abs(m(:))) + eps;
    imagesc(m, [-lim lim]); axis image off;
    colormap(bwr(256)); colorbar;
    title(ttls{k});
end


%% =======================================================================
%% Helper functions
%% =======================================================================
function row = lookup_row(fname, id_map, pid_map)
% Try several candidate keys derived from a filename against both maps.
    [~, stem, ~] = fileparts(fname);
    cands = {stem};
    for suf = {'_preprocessed','_unfiltered','_subjects'}
        cands{end+1} = erase(stem, suf{1}); %#ok<AGROW>
    end
    tok = strtok(stem, '_');                 % token before first underscore
    cands{end+1} = tok;
    cands = unique(cands, 'stable');

    for c = 1:numel(cands)
        key = cands{c};
        if isKey(id_map,  key), row = id_map(key);  return; end
        if isKey(pid_map, key), row = pid_map(key); return; end
    end
    row = NaN;
end

function v = read_rating(raw)
% Convert a table cell/string/number rating to double; blanks & DATA_EXPIRED -> NaN
    if iscell(raw), raw = raw{1}; end
    if isstring(raw) || ischar(raw)
        s = strtrim(string(raw));
        if s == "" || s == "DATA_EXPIRED", v = NaN; return; end
        v = str2double(s);
    else
        v = double(raw);
    end
end

function p_adj = fdr_bh(p_vals)
% Benjamini-Hochberg FDR adjustment.
    p_vals = p_vals(:);
    keep   = ~isnan(p_vals);
    p_adj  = nan(size(p_vals));
    pv     = p_vals(keep);
    m      = numel(pv);
    [p_sorted, sort_idx] = sort(pv);
    p_bh = p_sorted .* m ./ (1:m)';
    for i = m-1:-1:1
        p_bh(i) = min(p_bh(i), p_bh(i+1));
    end
    p_bh = min(p_bh, 1);
    tmp  = zeros(m,1);
    tmp(sort_idx) = p_bh;
    p_adj(keep)   = tmp;
end

function c = bwr(n)
% Blue-white-red diverging colormap (signed maps: white at zero).
    if nargin < 1, n = 256; end
    half = floor(n/2);
    b2w = [linspace(0.13,1,half)', linspace(0.40,1,half)', linspace(0.67,1,half)'];
    w2r = [linspace(1,0.78,n-half)', linspace(1,0.09,n-half)', linspace(1,0.18,n-half)'];
    c = [b2w; w2r];
end