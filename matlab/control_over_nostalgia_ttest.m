%% Pairwise t-test: Nostalgia vs Control, per country
%  Includes FDR correction, t-map & average-difference visualization.
%  Two output styles, both sharing the same global color scale:
%    1) Collective grid   — one panel per country + 'all' (2 figures: Tmap, AvgDiff)
%    2) Individual panels — one figure per country, per stat type (2 figures/country)
clear
close all

cfg       = read_config();
countries = cfg.countries;

output_folder = cfg.pic_pq1and3;
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
else
    delete(fullfile(output_folder, '*.png'));
    fprintf('Cleared existing pictures in %s\n', output_folder);
end

mask    = imread('mask.png');
in_mask = find(mask > 128);

base  = uint8(imread('base.png'));
base2 = base(10:531, 33:203, :);

n_countries = numel(countries);
results = struct('name', {}, 'NS', {}, 'tID', {}, 'tvals_sig', {}, 'diff_img', {});

%% Pass 1: compute per-country paired t-test, FDR threshold, sig-gated t-map, avg diff
for i = 1:n_countries
    country_name      = countries{i};
    preprocessed_dir  = fullfile(cfg.subjects_dir, country_name, 'preprocessed');
    if ~exist(preprocessed_dir, 'dir')
        fprintf('Directory not found: %s — skipping %s\n', preprocessed_dir, country_name);
        results(i) = empty_result(country_name);
        continue;
    end
    fprintf('\n%s Analyzing %s %s\n', repmat('=',1,20), country_name, repmat('=',1,20));
    results(i) = compute_country_stats(preprocessed_dir, country_name, mask, in_mask);
end

% Drop any countries that had no directory (kept as empty placeholders above
% so indexing stays aligned during the loop; excluded from here on)
valid = arrayfun(@(r) r.NS > 0, results);
results = results(valid);

%% Global color limits — shared by every figure below (grids AND individual panels)
M_t    = max(arrayfun(@(r) safe_max_abs(r.tvals_sig), results));
M_diff = max(arrayfun(@(r) safe_max_abs(r.diff_img), results));
if M_t == 0, M_t = 1; end
if M_diff == 0, M_diff = 1; end

tmap_cmap = build_hotcold_colormap(64, 1);          % cosmetic dead-zone; gating done via zeroed data
diff_cmap = build_hotcold_colormap_nogap(64);        % matches original diff colormap (no dead zone)

%% (1) Collective grids
plot_grid(results, 'tval', M_t, tmap_cmap, base2, mask, ...
    'Nostalgia < Control — T-test', ...
    fullfile(output_folder, sprintf('%sTmap_grid.png', cfg.pic_prefix)));
plot_grid(results, 'diff', M_diff, diff_cmap, base2, mask, ...
    'Nostalgia - Mean - Control difference', ...
    fullfile(output_folder, sprintf('%sAvgDiff_grid.png', cfg.pic_prefix)));

%% (2) Individual per-country panels — 2 figures per country, same global M's
for i = 1:numel(results)
    r = results(i);
    plot_country_panel(r, 'tval', M_t, tmap_cmap, base2, mask, ...
        output_folder, cfg.pic_prefix, 'Tmap');
    plot_country_panel(r, 'diff', M_diff, diff_cmap, base2, mask, ...
        output_folder, cfg.pic_prefix, 'AvgDiff');
end


%% ───────────────────────── Helper functions ─────────────────────────

function r = empty_result(country_name)
    r.name = country_name; r.NS = 0; r.tID = NaN;
    r.tvals_sig = []; r.diff_img = [];
end


function r = compute_country_stats(preprocessed_dir, country_name, mask, in_mask)
    if ~endsWith(preprocessed_dir, filesep)
        preprocessed_dir = [preprocessed_dir filesep];
    end
    fprintf('Processing: %s\n', preprocessed_dir);

    files = dir([preprocessed_dir '*.mat']);
    NS    = length(files);
    if NS == 0
        error('No .mat files found in: %s', preprocessed_dir);
    end
    fprintf('Found %d preprocessed files\n', NS);

    NC   = 2;
    data = zeros(length(in_mask), NS, NC);
    for s = 1:NS
        try
            ld = load([preprocessed_dir files(s).name]);
            data(:,s,1) = ld.control_avg(in_mask);
            data(:,s,2) = ld.nostalgia_avg(in_mask);
        catch ME
            fprintf('Warning: Could not load %s — %s\n', files(s).name, ME.message);
        end
    end

    tdata = zeros(length(in_mask),1);
    pdata = zeros(length(in_mask),1);
    for pix = 1:length(in_mask)
        [~,P,~,STATS] = ttest(data(pix,:,1), data(pix,:,2));
        tdata(pix) = STATS.tstat;
        pdata(pix) = P;
    end

    alltdata = tdata(isfinite(tdata));
    df  = NS - 1;
    P   = 1 - cdf('T', alltdata, df);
    FDR_val = 0.05;
    [pID, ~] = FDR_debug(P, FDR_val);
    tID = []; if ~isempty(pID), tID = icdf('T', 1-pID, df); end
    if isempty(tID) || isnan(tID)
        tID = 3;
    end
    fprintf('[%s] FDR threshold: t = %.3f (n=%d)\n', country_name, tID, NS);

    tvals_full = zeros(size(mask));
    tvals_full(in_mask) = tdata;
    tvals_full(~isfinite(tvals_full)) = 0;

    % Significance-gated: pixels below this country's own FDR threshold are
    % forced to exactly 0, landing them in the colormap's black zero-band
    % regardless of the shared color axis used later.
    tvals_sig = tvals_full;
    tvals_sig(tvals_sig < tID) = 0;

    avg_diff = mean(data(:,:,1),2) - mean(data(:,:,2),2);
    diff_img = zeros(size(mask));
    diff_img(in_mask) = avg_diff;
    diff_img(~isfinite(diff_img)) = 0;

    fprintf('Avg diff range: %.4f to %.4f\n', min(avg_diff), max(avg_diff));

    r.name      = country_name;
    r.NS        = NS;
    r.tID       = tID;
    r.tvals_sig = tvals_sig;
    r.diff_img  = diff_img;
end


function m = safe_max_abs(x)
    x = x(isfinite(x));
    if isempty(x), m = 0; else, m = max(abs(x(:))); end
end


function cmap = build_hotcold_colormap(NumCol, dead_zone_slots)
    hotmap  = hot(NumCol - dead_zone_slots);
    coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
    cmap    = [coldmap; zeros(2*dead_zone_slots, 3); hotmap];
end


function cmap = build_hotcold_colormap_nogap(NumCol)
    % Matches the original AvgDiff colormap: no black dead-zone at all,
    % since the diff map was never significance-gated in the source script.
    hotmap  = hot(NumCol);
    coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
    cmap    = [coldmap; hotmap];
end


function img = get_panel_img(r, kind)
    if strcmp(kind, 'tval'), img = r.tvals_sig; else, img = r.diff_img; end
end


function plot_grid(results, kind, M, cmap, base2, mask, fig_label, save_path)
    n = numel(results);
    ncols = 3; nrows = ceil(n/ncols);

    fig = figure('Color', [1 1 1]);
    t = tiledlayout(fig, nrows, ncols, 'TileSpacing', 'compact', 'Padding', 'compact');

    for i = 1:n
        r = results(i);
        img = get_panel_img(r, kind);
        nexttile(t);
        imagesc(base2); axis off; axis image; hold on;
        fh = imagesc(img, [-M M]);
        set(fh, 'AlphaData', mask);
        if strcmp(kind, 'tval')
            title(sprintf('%s (n=%d, t_{FDR}=%.2f)', r.name, r.NS, r.tID), 'FontSize', 10);
        else
            title(sprintf('%s (n=%d)', r.name, r.NS), 'FontSize', 10);
        end
    end
    colormap(fig, cmap);

    cb = colorbar;
    cb.Layout.Tile = 'east';

    sgtitle(sprintf('%s (shared color scale, |val| \\leq %.3f)', fig_label, M));
    saveas(fig, save_path);
end


function plot_country_panel(r, kind, M, cmap, base2, mask, output_folder, pic_prefix, name_tag)
    % One figure per country, using the SAME global M as the collective
    % grid — so a country's individual panel is numerically comparable to
    % its tile in the grid, just viewed in isolation.
    fig = figure('Name', sprintf('%s - %s', name_tag, r.name), 'NumberTitle', 'off', 'Color', [1 1 1]);

    subplot(1,2,1);
    imagesc(base2); axis off; axis equal; hold on;
    fh = imagesc(get_panel_img(r, kind), [-M M]);
    set(fh, 'AlphaData', mask);
    colormap(gca, cmap);
    if strcmp(kind, 'tval')
        title({sprintf('%s: Nostalgia < Control (%d subjects)', r.name, r.NS), ...
               sprintf('Threshold: t = %.2f (FDR q < 0.05)', r.tID)}, 'FontSize', 10);
    else
        title({sprintf('%s: Control - Nostalgia (%d subjects)', r.name, r.NS), ...
               'Mean difference'}, 'FontSize', 10);
    end

    subplot(1,2,2);
    imagesc(ones(size(base2)), [-M M]); axis off;
    colormap(gca, cmap); colorbar;
    if strcmp(kind, 'tval')
        title('T-statistic', 'FontSize', 10);
    else
        title('Mean difference', 'FontSize', 10);
    end

    saveas(fig, fullfile(output_folder, sprintf('%s%s_%s.png', pic_prefix, name_tag, r.name)));
end