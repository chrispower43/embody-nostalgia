%% Pixelwise one-sample t-test against zero for Control and Nostalgia
%  Includes FDR correction, t-map visualization, and saves figures.
clear
close all

cfg      = read_config();
countries = cfg.countries_all;   % {'BR','IN','US','SP','JP','all'}

% Create / clean output folder  (prefix keeps cohorts separate)
output_folder = cfg.pic_pq0;
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
else
    delete(fullfile(output_folder, '*.png'));
    fprintf('Cleared existing pictures in %s\n', output_folder);
end

for i = 1:length(countries)
    subdir       = countries{i};
    country_name = subdir;
    one_sample_ttest( ...
        fullfile(cfg.subjects_dir, subdir, 'preprocessed', filesep), ...
        country_name, i, output_folder, cfg.pic_prefix);
end


function one_sample_ttest(basepath, country_name, figure_number, output_folder, pic_prefix)

    mask     = imread('mask.png');
    in_mask  = find(mask > 128);
    fprintf('Mask dimensions: %d x %d\n', size(mask,1), size(mask,2));

    files = dir([basepath '*.mat']);
    NS    = length(files);
    NC    = 2;
    data  = zeros(length(in_mask), NS, NC);
    fprintf('Loading %d subjects...\n', NS);

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
    df  = NS - 1;
    FDR_val = 0.05;
    P_all   = 1 - cdf('T', alltdata, df);
    [pID, ~] = FDR_debug(P_all, FDR_val);
    tID = icdf('T', 1 - pID, df);

    if strcmp(country_name,'all'), M = 10; else, M = 8; end
    NumCol = 64;

    if isempty(tID)
        tID = 3;
        th_label = sprintf('Threshold: t = %.2f (uncorrelated)', tID);
    else
        th_label = sprintf('Threshold: t = %.2f', tID);
    end
    fprintf('FDR threshold: %.3f\n', tID);

    non_sig  = round(tID / M * NumCol);
    hotmap   = hot(NumCol - non_sig);
    coldmap  = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
    hotcoldmap = [coldmap; zeros(2*non_sig,3); hotmap];

    tvals_for_plot = zeros(size(mask,1), size(mask,2), NC);
    for condit = 1:NC
        temp = zeros(size(mask));
        temp(in_mask) = tdata(:,condit);
        temp(~isfinite(temp)) = 0;
        tvals_for_plot(:,:,condit) = temp;
    end

    labels = {'Control','Nostalgia'};
    base   = imread('base.png');
    base2  = base(10:531, 33:203, :);

    fig1 = figure(figure_number);
    for n = 1:NC
        subplot(1, 3, n);
        imagesc(base2); axis off; axis equal; hold on;
        set(gcf, 'Color', [1 1 1]);
        fh = imagesc(tvals_for_plot(:,:,n), [-M M]);
        set(fh, 'AlphaData', mask);
        colormap(hotcoldmap);
        title(labels{n}, 'FontSize', 12);
    end
    subplot(1, 3, NC+1);
    imagesc(ones(size(base2)), [-M M]); axis off; colorbar;
    set(gcf, 'Name', ['T-maps: ' country_name], 'NumberTitle', 'off');
    title({sprintf('%s: T-test vs zero - %d subjects', country_name, NS), th_label}, 'FontSize', 10);

    % Prefix in filename keeps outputs from different cohorts separate
    saveas(fig1, fullfile(output_folder, sprintf('%sTmap_%s.png', pic_prefix, country_name)));

    %% Mean maps
    mean_control    = mean(data(:,:,1), 2);
    mean_nostalgia  = mean(data(:,:,2), 2);
    mean_control_img   = zeros(size(mask)); mean_control_img(in_mask)   = mean_control;
    mean_nostalgia_img = zeros(size(mask)); mean_nostalgia_img(in_mask) = mean_nostalgia;
    Mmean = max(abs([mean_control; mean_nostalgia]));
    if Mmean == 0, Mmean = 1; end

    NumCol  = 64;
    non_sig = round(0.05 * NumCol);
    hotmap  = hot(NumCol - non_sig);
    coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
    hotcoldmap = [coldmap; zeros(2*non_sig,3); hotmap];

    base  = uint8(imread('base.png'));
    base2 = base(10:531, 33:203, :);

    fig2 = figure(99);
    set(gcf, 'Color', [1 1 1]);
    titles = {'Mean Control','Mean Nostalgia'};
    for c = 1:2
        subplot(1,3,c);
        imagesc(base2); axis off; axis equal; hold on;
        if c == 1, fh = imagesc(mean_control_img, [-Mmean Mmean]);
        else,      fh = imagesc(mean_nostalgia_img, [-Mmean Mmean]); end
        colormap(hotcoldmap); set(fh, 'AlphaData', mask);
        title(titles{c}, 'FontSize', 10);
    end
    subplot(1,3,3);
    imagesc(ones(size(base2)), [-Mmean Mmean]); axis off; colormap(hotcoldmap); colorbar;
    title(sprintf('%s: Mean activation', country_name), 'FontSize', 10);

    saveas(fig2, fullfile(output_folder, sprintf('%sMeanMaps_%s.png', pic_prefix, country_name)));
end