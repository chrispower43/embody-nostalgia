%% Pairwise t-test: Nostalgia vs Control, per country
clear
close all

cfg       = read_config();
countries = cfg.countries_all;

output_folder = cfg.pic_pq1and3;
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
else
    delete(fullfile(output_folder, '*.png'));
    fprintf('Cleared existing pictures in %s\n', output_folder);
end

for i = 1:length(countries)
    country         = countries{i};
    preprocessed_dir = fullfile(cfg.subjects_dir, country, 'preprocessed');
    if exist(preprocessed_dir, 'dir')
        fprintf('\n%s Analyzing %s %s\n', repmat('=',1,20), country, repmat('=',1,20));
        run_pairwise_ttest_by_country(preprocessed_dir, country, output_folder, cfg.pic_prefix);
    else
        fprintf('Directory not found: %s\n', preprocessed_dir);
    end
end


function run_pairwise_ttest_by_country(preprocessed_dir, country_name, output_folder, pic_prefix)

    if ~endsWith(preprocessed_dir, filesep)
        preprocessed_dir = [preprocessed_dir filesep];
    end
    fprintf('Processing: %s\n', preprocessed_dir);

    mask    = imread('mask.png');
    in_mask = find(mask > 128);

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
        [~,P,~,STATS] = ttest(data(pix,:,2), data(pix,:,1));
        tdata(pix) = STATS.tstat;
        pdata(pix) = P;
    end

    alltdata = tdata(isfinite(tdata));
    df  = NS - 1;
    P   = 1 - cdf('T', alltdata, df);
    FDR_val = 0.05;
    [pID, pN] = FDR_debug(P, FDR_val);
    tID = []; if ~isempty(pID), tID = icdf('T', 1-pID, df); end
    tN  = icdf('T', 1-pN, df); %#ok<NASGU>

    M = max(abs(tdata)); if M==0, M=1; end
    NumCol = 64;
    if isempty(tID)
        th = 3; th_label = 'Threshold: t = 3.00 (uncorrelated)';
    else
        th = tID; th_label = sprintf('Threshold: t = %.2f (FDR q < %.2f)', th, FDR_val);
    end

    non_sig    = round(th/M*NumCol);
    hotmap     = hot(NumCol - non_sig);
    coldmap    = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
    hotcoldmap = [coldmap; zeros(2*non_sig,3); hotmap];

    tvals_for_plot = zeros(size(mask));
    tvals_for_plot(in_mask) = tdata;
    tvals_for_plot(~isfinite(tvals_for_plot)) = 0;

    base  = uint8(imread('base.png'));
    base2 = base(10:531, 33:203, :);

    fig1 = figure('Name', sprintf('T-map - %s', country_name), 'NumberTitle', 'off');
    set(gcf, 'Color', [1 1 1]);
    subplot(1,2,1); imagesc(base2); axis off; axis equal; hold on;
    title({sprintf('%s: Nostalgia > Control (%d subjects)', country_name, NS), th_label}, 'FontSize', 10);
    fh = imagesc(tvals_for_plot, [-M M]);
    colormap(hotcoldmap); set(fh, 'AlphaData', mask);
    subplot(1,2,2); imagesc(ones(size(base2)), [-M M]); axis off;
    colormap(hotcoldmap); colorbar; title('T-statistic', 'FontSize', 10);

    saveas(fig1, fullfile(output_folder, sprintf('%sTmap_%s.png', pic_prefix, country_name)));

    %% Average difference maps
    avg_diff = mean(data(:,:,2),2) - mean(data(:,:,1),2);
    diff_for_plot = zeros(size(mask));
    diff_for_plot(in_mask) = avg_diff;
    diff_for_plot(~isfinite(diff_for_plot)) = 0;

    diff_range = max(abs(avg_diff)); if diff_range==0, diff_range=1; end
    diff_hotmap  = hot(64);
    diff_coldmap = flipud([diff_hotmap(:,3) diff_hotmap(:,2) diff_hotmap(:,1)]);
    diff_colormap = [diff_coldmap; diff_hotmap];

    fig2 = figure('Name', sprintf('Avg Diff - %s', country_name), 'NumberTitle', 'off');
    set(gcf, 'Color', [1 1 1]);
    subplot(1,2,1); imagesc(base2); axis off; axis equal; hold on;
    title({sprintf('%s: Nostalgia - Control (%d subjects)', country_name, NS), 'Mean difference'}, 'FontSize', 10);
    fh2 = imagesc(diff_for_plot, [-diff_range diff_range]);
    colormap(diff_colormap); set(fh2, 'AlphaData', mask);
    subplot(1,2,2); imagesc(ones(size(base2)), [-diff_range diff_range]);
    axis off; colormap(diff_colormap); colorbar; title('Mean difference', 'FontSize', 10);

    saveas(fig2, fullfile(output_folder, sprintf('%sAvgDiff_%s.png', pic_prefix, country_name)));
    fprintf('Avg diff range: %.4f to %.4f\n', min(avg_diff), max(avg_diff));
end