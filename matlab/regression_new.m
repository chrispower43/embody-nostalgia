%% Pixel-level Regression: Bodily Sensation ~ Positive/Negative Feelings
%
% For each pixel, fits two simple OLS regressions across all trials
% (pooled across subjects and song conditions):
%
%   pixel_value ~ beta0 + beta1 * pos_rating   (Model 1)
%   pixel_value ~ beta0 + beta1 * neg_rating   (Model 2)
%
% Uses unfiltered .mat files from final&new_subjects/all/unfiltered/
% and survey ratings from combined_data_all.csv.

clear; clc;

%% ── 0.  Paths ────────────────────────────────────────────────────────────
data_dir  = fullfile('final&new_subjects', 'all', 'unfiltered');
csv_path  = 'combined_data_all.csv';

IMG_H = 522;
IMG_W = 171;

%% ── 1.  Load survey CSV ──────────────────────────────────────────────────
fprintf('Loading survey data from %s ...\n', csv_path);
opts = detectImportOptions(csv_path, 'TextType', 'string', ...
                           'VariableNamingRule', 'preserve');
survey = readtable(csv_path, opts);

% Helper to fetch a column by its original header (preserve mode keeps names
% like 'N1_pos' intact, but spaces in demographic columns are also preserved).
getcol = @(name) survey.(name);

% Treat DATA_EXPIRED as missing in the rating columns when we read them later.

%% ── 2.  Build lookup maps for BOTH possible filename keys ────────────────
% Files may be named by the short ID (e.g. 1FQb6PSo35pS4aT) OR by the long
% PROLIFIC_PID (e.g. 68dd6ada1c06b7f58ff4020c). We index both.
ids  = string(survey.('ID'));
pids = string(survey.('PROLIFIC_PID'));

id_map  = containers.Map(ids,  num2cell(1:height(survey)));
pid_map = containers.Map(pids, num2cell(1:height(survey)));

%% ── 3.  Trial definitions ────────────────────────────────────────────────
trial_prefixes = {'N1','N2','N3','N4','C1','C2','C3','C4'};

prefix2field = containers.Map( ...
    {'N1','N2','N3','N4','C1','C2','C3','C4'}, ...
    {'Nost1','Nost2','Nost3','Nost4','Cont1','Cont2','Cont3','Cont4'});

%% ── 4.  List files + DIAGNOSTIC printout ─────────────────────────────────
fprintf('Scanning unfiltered .mat files in %s ...\n', data_dir);
mat_files = dir(fullfile(data_dir, '*.mat'));
if isempty(mat_files)
    error('No .mat files found in %s', data_dir);
end

fprintf('\n--- DIAGNOSTIC ---\n');
fprintf('Sample CSV ID column        : %s\n', strjoin(cellstr(ids(1:min(3,end)))', ', '));
fprintf('Sample CSV PROLIFIC_PID col : %s\n', strjoin(cellstr(pids(1:min(3,end)))', ', '));
nshow = min(3, numel(mat_files));
fprintf('Sample .mat filenames       : %s\n', ...
        strjoin({mat_files(1:nshow).name}, ', '));
fprintf('------------------\n\n');

%% ── 5.  Accumulate sufficient stats for OLS, pixel-by-pixel ──────────────
n_pix = IMG_H * IMG_W;

acc_pos = struct('n',zeros(n_pix,1),'sx',zeros(n_pix,1),'sy',zeros(n_pix,1), ...
                 'sx2',zeros(n_pix,1),'sxy',zeros(n_pix,1),'sy2',zeros(n_pix,1));
acc_neg = acc_pos;

n_trials_loaded = 0;
n_skipped       = 0;

for f = 1:numel(mat_files)
    mat_path = fullfile(data_dir, mat_files(f).name);
    [~, fname] = fileparts(mat_files(f).name);

    % Generate candidate subject keys from the filename:
    %   - full stem
    %   - stem with common suffixes stripped (_unfiltered/_preprocessed/_subjects)
    %   - token before the first underscore
    cand = unique(string({ ...
        fname, ...
        regexprep(fname, '_(unfiltered|preprocessed|subjects)$', ''), ...
        char(extractBefore(string(fname) + "_", "_")) ...
    }), 'stable');

    % Resolve to a survey row via either map
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
        n_skipped = n_skipped + 1;
        continue
    end

    S = load(mat_path);

    for t = 1:numel(trial_prefixes)
        pfx   = trial_prefixes{t};
        field = prefix2field(pfx);
        if ~isfield(S, field), continue; end

        pixel_map = S.(field);
        if ~isequal(size(pixel_map), [IMG_H, IMG_W])
            warning('Unexpected size for %s field %s - skipping', fname, field);
            continue
        end

        pos_val = read_rating(survey, [pfx '_pos'], row);
        neg_val = read_rating(survey, [pfx '_neg'], row);
        if isnan(pos_val) && isnan(neg_val), continue; end

        y = double(pixel_map(:));

        if ~isnan(pos_val)
            acc_pos.n   = acc_pos.n   + 1;
            acc_pos.sx  = acc_pos.sx  + pos_val;
            acc_pos.sy  = acc_pos.sy  + y;
            acc_pos.sx2 = acc_pos.sx2 + pos_val^2;
            acc_pos.sxy = acc_pos.sxy + pos_val .* y;
            acc_pos.sy2 = acc_pos.sy2 + y.^2;
        end
        if ~isnan(neg_val)
            acc_neg.n   = acc_neg.n   + 1;
            acc_neg.sx  = acc_neg.sx  + neg_val;
            acc_neg.sy  = acc_neg.sy  + y;
            acc_neg.sx2 = acc_neg.sx2 + neg_val^2;
            acc_neg.sxy = acc_neg.sxy + neg_val .* y;
            acc_neg.sy2 = acc_neg.sy2 + y.^2;
        end
        n_trials_loaded = n_trials_loaded + 1;
    end

    if mod(f,50)==0
        fprintf('  Processed %d / %d files ...\n', f, numel(mat_files));
    end
end

fprintf('Done. Trials loaded: %d  |  Subjects skipped (no CSV match): %d\n', ...
        n_trials_loaded, n_skipped);

if n_trials_loaded == 0
    error(['No trials matched. Check the DIAGNOSTIC block above: compare the ', ...
           'filename format against the ID / PROLIFIC_PID columns.']);
end

%% ── 6.  OLS coefficients, t-stats, p-values ──────────────────────────────
fprintf('Computing regressions ...\n');
[beta_pos, t_pos, p_pos] = ols_from_accumulators(acc_pos);
[beta_neg, t_neg, p_neg] = ols_from_accumulators(acc_neg);

beta_pos = reshape(beta_pos, IMG_H, IMG_W);
t_pos    = reshape(t_pos,    IMG_H, IMG_W);
p_pos    = reshape(p_pos,    IMG_H, IMG_W);
beta_neg = reshape(beta_neg, IMG_H, IMG_W);
t_neg    = reshape(t_neg,    IMG_H, IMG_W);
p_neg    = reshape(p_neg,    IMG_H, IMG_W);

%% ── 6b.  Load body mask (for silhouette plotting + multiple comparisons) ─
% Same convention as the old PCA code: pixels with value > 128 are "inside".
mask_path = 'mask.png';
if exist(mask_path, 'file')
    mask = imread(mask_path);
    if ndims(mask) == 3, mask = mask(:,:,1); end      % use 1st channel if RGB
    if ~isequal(size(mask), [IMG_H, IMG_W])
        warning('mask size %s differs from data %dx%d; attempting resize.', ...
                mat2str(size(mask)), IMG_H, IMG_W);
        try
            mask = imresize(mask, [IMG_H, IMG_W]);     % needs Image Proc Toolbox
        catch
            warning('Could not resize mask; plotting full frame.');
            mask = 255*ones(IMG_H, IMG_W, 'uint8');
        end
    end
    in_mask = mask > 128;                              % logical [522 x 171]
else
    warning('mask.png not found - plotting full frame without silhouette.');
    in_mask = true(IMG_H, IMG_W);
end
n_in_mask = nnz(in_mask);
fprintf('Pixels inside mask: %d / %d\n', n_in_mask, n_pix);

%% ── 7.  FDR correction (Benjamini–Hochberg), restricted to in-mask pixels ─
% Multiple-comparison correction should only span body pixels, not background.
p_pos_fdr = nan(IMG_H, IMG_W);
p_neg_fdr = nan(IMG_H, IMG_W);
p_pos_fdr(in_mask) = fdr_bh(p_pos(in_mask));
p_neg_fdr(in_mask) = fdr_bh(p_neg(in_mask));

%% ── 8.  Save ─────────────────────────────────────────────────────────────
save('pixel_regression_results.mat', ...
     'beta_pos','t_pos','p_pos','p_pos_fdr', ...
     'beta_neg','t_neg','p_neg','p_neg_fdr');
fprintf('Results saved to pixel_regression_results.mat\n');

%% ── 9.  Visualise (silhouette style, matching the old PCA-code figures) ──
alpha_thresh = 0.05;
cmap = make_hotcold(64);     % black-centred hot/cold map (0 = black)

% Significance masks (in-mask only)
sig_pos = in_mask & (p_pos_fdr < alpha_thresh);
sig_neg = in_mask & (p_neg_fdr < alpha_thresh);

figure('Name','Pixel Regression Results','NumberTitle','off', ...
       'Color','w','Position',[100 100 1200 800]);

% Row 1: positive feelings
plot_body(subplot(2,3,1), beta_pos, in_mask, cmap, '\beta - Positive Feelings');
plot_body(subplot(2,3,2), t_pos,    in_mask, cmap, 't-stat - Positive Feelings');
plot_body_masked(subplot(2,3,3), beta_pos, in_mask, sig_pos, cmap, ...
                 sprintf('\\beta sig (FDR p<%.2f) - Positive', alpha_thresh));

% Row 2: negative feelings
plot_body(subplot(2,3,4), beta_neg, in_mask, cmap, '\beta - Negative Feelings');
plot_body(subplot(2,3,5), t_neg,    in_mask, cmap, 't-stat - Negative Feelings');
plot_body_masked(subplot(2,3,6), beta_neg, in_mask, sig_neg, cmap, ...
                 sprintf('\\beta sig (FDR p<%.2f) - Negative', alpha_thresh));

sgtitle('Bodily Sensation Pixel Regression');

% Save figure alongside the .mat, mirroring the old workflow
pictures_dir = fullfile('pictures','regression');
if ~exist(pictures_dir,'dir'), mkdir(pictures_dir); end
saveas(gcf, fullfile(pictures_dir,'pixel_regression_maps.png'));
fprintf('Saved figure to %s\n', fullfile(pictures_dir,'pixel_regression_maps.png'));

fprintf('\nSummary (FDR p < %.2f, in-mask pixels only):\n', alpha_thresh);
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
end

function [beta1, tstat, pval] = ols_from_accumulators(acc)
% Simple linear regression y = b0 + b1*x from accumulated sufficient stats.
    n=acc.n; sx=acc.sx; sy=acc.sy; sx2=acc.sx2; sxy=acc.sxy; sy2=acc.sy2;

    denom = n.*sx2 - sx.^2;                 % = n*Sxx
    beta1 = (n.*sxy - sx.*sy) ./ denom;
    beta1(denom==0) = 0;

    beta0 = (sy - beta1.*sx) ./ n;

    SSres = sy2 - 2*beta0.*sy - 2*beta1.*sxy ...
            + n.*beta0.^2 + 2*beta0.*beta1.*sx + beta1.^2.*sx2;
    SSres = max(SSres, 0);

    df     = n - 2;
    s2     = SSres ./ max(df,1);
    Sxx    = sx2 - sx.^2 ./ n;
    var_b1 = s2 ./ max(Sxx, eps);

    tstat = beta1 ./ sqrt(var_b1);
    tstat(df < 1) = 0;

    pval = 2 * (1 - tcdf(abs(tstat), max(df,1)));
    pval(df < 1) = 1;

    beta1=beta1(:); tstat=tstat(:); pval=pval(:);
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
% Black-centred hot/cold colormap (replicates the old PCA-code 'hotcoldmap').
% Lower half: cold ramp (cyan/blue -> black). Upper half: hot (black -> red ->
% yellow -> white). With symmetric caxis, zero maps to the black midpoint.
    if nargin < 1, numcol = 64; end
    hotmap  = hot(numcol);
    coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);  % swap R/B, flip
    cmap    = [coldmap; hotmap];
end

function M = robust_M(vals)
% Symmetric display limit from the 99th percentile of |values| (ignores zeros
% and NaNs), so a few extreme pixels don't wash out the map.
    v = vals(:);
    v = v(~isnan(v) & v ~= 0);
    if isempty(v), M = 1; return; end
    M = prctile(abs(v), 99);
    if M <= 0 || isnan(M), M = max(abs(v)) + eps; end
end

function plot_body(ax, map2d, in_mask, cmap, ttl)
% Draw a 522x171 map as a body silhouette: out-of-mask pixels -> NaN
% (transparent), symmetric color limits, black-centred colormap.
    img = nan(size(map2d));
    img(in_mask) = map2d(in_mask);
    M = robust_M(img(in_mask));
    imagesc(ax, img, [-M M]);
    set(ax, 'Color', 'w');           % background behind transparent NaNs
    axis(ax, 'image'); axis(ax, 'off');
    colormap(ax, cmap); colorbar(ax);
    title(ax, ttl);
end

function plot_body_masked(ax, beta2d, in_mask, sig_mask, cmap, ttl)
% Like plot_body, but only significant pixels show colour; the rest of the
% body is set to 0 (black midpoint) so the silhouette is still visible.
    img = nan(size(beta2d));
    img(in_mask)  = 0;                       % black body
    img(sig_mask) = beta2d(sig_mask);        % colour only where significant
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