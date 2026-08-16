%% Pixelwise one-sample t-test against zero for Control and Nostalgia
%  Includes FDR correction, t-map & mean-map visualization.
%  Two output styles, both sharing the same global color scale per condition:
%    1) Collective grid  — one panel per country + 'all', per condition (4 figures)
%    2) Individual panels — one figure per country, per stat type (2 figures/country)
function zero_ttest(~)
    close all
    
    cfg       = read_config();
    
   if nargin < 1
        countries = cfg.countries;
        output_folder = [cfg.pic_pq0];
        if ~exist(output_folder, 'dir')
            mkdir(output_folder);
        else
            delete(fullfile(output_folder, '*.png'));
            fprintf('Cleared existing pictures in %s\n', output_folder);
        end
    else 
        countries = cfg.countries_all;
        output_folder = [cfg.pic_pq0, '_all'];
        if ~exist(output_folder, 'dir')
            mkdir(output_folder);
        else
            delete(fullfile(output_folder, '*.png'));
            fprintf('Cleared existing pictures in %s\n', output_folder);
        end
    end
    
    mask    = imread('mask.png');
    in_mask = find(mask > 128);
    fprintf('Mask dimensions: %d x %d\n', size(mask,1), size(mask,2));
    
    base  = uint8(imread('base.png'));
    base2 = base(10:531, 33:203, :);
    
    n_countries = numel(countries);
    results = struct('name', {}, 'NS', {}, 'tID', {}, 'tvals_sig', {}, ...
                      'mean_control_img', {}, 'mean_nostalgia_img', {}, 'Mmean', {});
    
    %% Pass 1: compute per-country t-test, FDR threshold, sig-gated t-maps, mean maps
    for i = 1:n_countries
        country_name = countries{i};
        basepath = fullfile(cfg.subjects_dir, country_name, 'preprocessed', filesep);
        results(i) = compute_country_stats(basepath, country_name, mask, in_mask);
    end
    
    %% Global color limits — one per condition, shared by EVERY figure below,
    %  both the collective grids and the individual per-country panels.
    M_nost = max(arrayfun(@(r) safe_max_abs(r.tvals_sig(:,:,2)), results));
    M_cont = max(arrayfun(@(r) safe_max_abs(r.tvals_sig(:,:,1)), results));
    if M_nost == 0, M_nost = 1; end
    if M_cont == 0, M_cont = 1; end
    
    M_mean_nost = max(arrayfun(@(r) safe_max_abs(r.mean_nostalgia_img), results));
    M_mean_cont = max(arrayfun(@(r) safe_max_abs(r.mean_control_img), results));
    if M_mean_nost == 0, M_mean_nost = 1; end
    if M_mean_cont == 0, M_mean_cont = 1; end
    
    tmap_cmap = build_hotcold_colormap(64, 1);                 % cosmetic dead-zone; gating is via zeroed data
    meanmap_cmap = build_hotcold_colormap(64, round(0.05*64)); % no gating for means, dead-zone is cosmetic only
    
    %% (1) Collective grids — 4 figures total
    plot_grid(results, 'tval', 2, M_nost, tmap_cmap, base2, mask, 'Nostalgia — T-test vs zero', ...
        fullfile(output_folder, sprintf('%sTmap_grid_Nostalgia.png', cfg.pic_prefix)));
    plot_grid(results, 'tval', 1, M_cont, tmap_cmap, base2, mask, 'Control — T-test vs zero', ...
        fullfile(output_folder, sprintf('%sTmap_grid_Control.png', cfg.pic_prefix)));
    plot_grid(results, 'mean', 2, M_mean_nost, meanmap_cmap, base2, mask, 'Nostalgia — Mean activation', ...
        fullfile(output_folder, sprintf('%sMeanMap_grid_Nostalgia.png', cfg.pic_prefix)));
    plot_grid(results, 'mean', 1, M_mean_cont, meanmap_cmap, base2, mask, 'Control — Mean activation', ...
        fullfile(output_folder, sprintf('%sMeanMap_grid_Control.png', cfg.pic_prefix)));
    
    %% (2) Individual per-country panels — 2 figures per country, same global M's
    for i = 1:n_countries
        r = results(i);
        plot_country_panel(r, 'tval', M_cont, M_nost, tmap_cmap, base2, mask, ...
            output_folder, cfg.pic_prefix, 'Tmap');
        plot_country_panel(r, 'mean', M_mean_cont, M_mean_nost, meanmap_cmap, base2, mask, ...
            output_folder, cfg.pic_prefix, 'MeanMap');
    end
end

%% ───────────────────────── Helper functions ─────────────────────────

function r = compute_country_stats(basepath, country_name, mask, in_mask)
    files = dir([basepath '*.mat']);
    NS    = length(files);
    NC    = 2;
    data  = zeros(length(in_mask), NS, NC);
    fprintf('[%s] Loading %d subjects...\n', country_name, NS);

    for s = 1:NS
        loaded_data = load([basepath files(s).name]);
        data(:, s, 1) = loaded_data.control_avg(in_mask);
        data(:, s, 2) = loaded_data.nostalgia_avg(in_mask);
    end

    tdata = zeros(length(in_mask), NC);
    pvals = zeros(length(in_mask), NC);
    for condit = 1:NC
        [~, P, ~, STATS] = ttest(data(:,:,condit)');
        tdata(:,condit) = STATS.tstat;
        pvals(:,condit) = P;
    end

    alltdata = tdata(:);
    alltdata(~isfinite(alltdata)) = [];
    df      = NS - 1;
    FDR_val = 0.05;
    P_all   = 1 - cdf('T', alltdata, df);
    [pID, ~] = FDR_debug(P_all, FDR_val);
    tID = icdf('T', 1 - pID, df);
    if isempty(tID) || isnan(tID)
        tID = 3;
    end
    fprintf('[%s] FDR threshold: t = %.3f (n=%d)\n', country_name, tID, NS);

    tvals_full = zeros(size(mask,1), size(mask,2), NC);
    for condit = 1:NC
        temp = zeros(size(mask));
        temp(in_mask) = tdata(:,condit);
        temp(~isfinite(temp)) = 0;
        tvals_full(:,:,condit) = temp;
    end

    % Significance-gated t-maps: pixels below this country's own FDR
    % threshold are forced to exactly 0 (lands in the colormap's black
    % zero-band), regardless of the shared color axis used later.
    tvals_sig = tvals_full;
    tvals_sig(abs(tvals_sig) < tID) = 0;

    mean_control    = mean(data(:,:,1), 2);
    mean_nostalgia  = mean(data(:,:,2), 2);
    mean_control_img   = zeros(size(mask)); mean_control_img(in_mask)   = mean_control;
    mean_nostalgia_img = zeros(size(mask)); mean_nostalgia_img(in_mask) = mean_nostalgia;
    Mmean = max(abs([mean_control; mean_nostalgia]));
    if Mmean == 0, Mmean = 1; end

    r.name               = country_name;
    r.NS                 = NS;
    r.tID                = tID;
    r.tvals_sig          = tvals_sig;
    r.mean_control_img   = mean_control_img;
    r.mean_nostalgia_img = mean_nostalgia_img;
    r.Mmean              = Mmean;
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


function img = get_panel_img(r, kind, condit)
    % kind: 'tval' or 'mean'; condit: 1=Control, 2=Nostalgia
    if strcmp(kind, 'tval')
        img = r.tvals_sig(:,:,condit);
    else
        if condit == 1, img = r.mean_control_img; else, img = r.mean_nostalgia_img; end
    end
end


function plot_grid(results, kind, condit, M, cmap, base2, mask, fig_label, save_path)
    n = numel(results);
    ncols = 3; nrows = ceil(n/ncols);

    fig = figure('Color', [1 1 1]);
    t = tiledlayout(fig, nrows, ncols, 'TileSpacing', 'compact', 'Padding', 'compact');

    for i = 1:n
        r = results(i);
        img = get_panel_img(r, kind, condit);
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


function plot_country_panel(r, kind, M_cont, M_nost, cmap, base2, mask, output_folder, pic_prefix, name_tag)
    % One figure per country: Control | Nostalgia | colorbar(s).
    % Uses the SAME global M_cont / M_nost as the collective grids, so a
    % given country's individual panel is numerically comparable to its
    % counterpart in the grid — just viewed in isolation.
    fig = figure('Color', [1 1 1]);

    subplot(1, 3, 1);
    imagesc(base2); axis off; axis equal; hold on;
    fh = imagesc(get_panel_img(r, kind, 1), [-M_cont M_cont]);
    set(fh, 'AlphaData', mask);
    colormap(gca, cmap);
    title('Control', 'FontSize', 12);

    subplot(1, 3, 2);
    imagesc(base2); axis off; axis equal; hold on;
    fh = imagesc(get_panel_img(r, kind, 2), [-M_nost M_nost]);
    set(fh, 'AlphaData', mask);
    colormap(gca, cmap);
    title('Nostalgia', 'FontSize', 12);

    % Control and Nostalgia keep their own global M (may differ), so two
    % colorbars are shown rather than implying a single shared scale
    % between the two conditions.
    subplot(1, 3, 3);
    axis off;
    cb1 = colorbar('Position', [0.68 0.15 0.03 0.7]);
    caxis(gca, [-M_cont M_cont]); colormap(gca, cmap);
    ylabel(cb1, 'Control t/mean');

    if strcmp(kind, 'tval')
        stat_label = sprintf('T-test vs zero — %d subjects, t_{FDR}=%.2f', r.NS, r.tID);
    else
        stat_label = sprintf('Mean activation — %d subjects', r.NS);
    end
    sgtitle(sprintf('%s: %s', r.name, stat_label));

    saveas(fig, fullfile(output_folder, sprintf('%s%s_%s.png', pic_prefix, name_tag, r.name)));
end