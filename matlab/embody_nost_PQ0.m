%% Pixelwise one-sample t-test against zero for Control and Nostalgia
% Includes FDR correction, t-map visualization, and saves figures

clear 
close all

% Ensure output folder exists
output_folder = './pictures/PQ0';
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
else
    % Delete all existing pictures in the PQ0 directory
    delete([output_folder '/*.png']);
    fprintf('Deleted all existing pictures in %s\n', output_folder);
end

countries = {'all','BR','JP','US','IN','SP'};
%countries = {'BR','US','IN','SP'};

for i = 1:length(countries)
    subdir = countries{i};
    country_name = strrep(subdir, '/', ''); % Remove trailing slash for display
    one_sample_ttest(['final&new_subjects/' subdir '/preprocessed/'], country_name, i, output_folder);
end

function one_sample_ttest(basepath, country_name, figure_number, output_folder)

    %% Load mask and setup
    mask = imread('mask.png');
    in_mask = find(mask > 128);
    fprintf('Mask dimensions: %d x %d\n', size(mask, 1), size(mask, 2));
    
    %% Load all subjects
    files = dir([basepath '*.mat']);
    NS = length(files);
    NC = 2; % Control and Nostalgia
    data = zeros(length(in_mask), NS, NC);
    
    fprintf('Loading %d subjects...\n', NS);
    
    for s = 1:NS
        loaded_data = load([basepath files(s).name]);
        data(:, s, 1) = loaded_data.control_avg(in_mask);
        data(:, s, 2) = loaded_data.nostalgia_avg(in_mask);
    end
    
    %% Run one-sample t-test against zero for each condition
    tdata = zeros(length(in_mask), NC);
    pvals = zeros(length(in_mask), NC);
    
    for condit = 1:NC
        [~, P, ~, STATS] = ttest(data(:, :, condit)');
        tdata(:, condit) = STATS.tstat;
        pvals(:, condit) = P;
    end
    
    %% Multiple comparisons correction (FDR)
    alltdata = tdata(:);
    alltdata(~isfinite(alltdata)) = [];
    
    df = NS - 1; % degrees of freedom
    FDR_val = 0.05;
    
    P_all = 1 - cdf('T', alltdata, df);
    [pID, pN] = FDR_debug(P, FDR_val); % Benjamini-Hochberg at q=0.05
    tID = icdf('T', 1 - pID, df);
    tN = icdf('T', 1 - pN, df);
    
    fprintf('FDR threshold (indep/pos corr): %.3f\n', tID);
    
    %% Prepare visualization
    if strcmp(country_name,'all')
        M=10;
    else 
        M=8;
    end
    
    NumCol = 64;
    
    if isempty(tID)
        tID = 3; % fallback uncorrected threshold
        fprintf('Using uncorrected threshold 3\n')
        th_label = sprintf('Threshold: t = %.2f (uncorrelated)', tID);
    else
        th_label = sprintf('Threshold: t = %.2f', tID);
    end
    
    non_sig = round(tID / M * NumCol);
    hotmap = hot(NumCol - non_sig);
    coldmap = flipud([hotmap(:, 3) hotmap(:, 2) hotmap(:, 1)]);
    hotcoldmap = [
        coldmap;
        zeros(2 * non_sig, 3);
        hotmap
    ];
    
    %% Reshape t-values into 2D maps
    tvals_for_plot = zeros(size(mask, 1), size(mask, 2), NC);
    for condit = 1:NC
        temp = zeros(size(mask));
        temp(in_mask) = tdata(:, condit);
        temp(~isfinite(temp)) = 0;
        tvals_for_plot(:, :, condit) = temp;
    end
    
    %% Plot t-maps
    labels = {'Control', 'Nostalgia'};
    
    base = imread('base.png');
    base2 = base(10:531, 33:203, :);
    
    plotcols = 3;
    plotrows = 1;
    
    fprintf('Plotting t-maps...\n');
    
    % Create a new figure for each country
    fig1 = figure(figure_number);
    
    for n = 1:NC
        subplot(plotrows, plotcols, n)
        imagesc(base2);
        axis('off'); axis equal;
        set(gcf, 'Color', [1 1 1]);
        hold on;
    
        over2 = tvals_for_plot(:, :, n);
        fh = imagesc(over2, [-M, M]);
        set(fh, 'AlphaData', mask);
        colormap(hotcoldmap);
        title(labels{n}, 'FontSize', 12);
    end
    
    % Add colorbar
    subplot(plotrows, plotcols, NC + 1)
    imagesc(ones(size(base2)), [-M, M]);
    axis('off');
    colorbar;
    
    % Set window name to show country
    set(gcf, 'Name', ['T-maps: ' country_name], 'NumberTitle', 'off');
    
    title({sprintf('%s: T-test against zero - %d subjects', country_name, NS), th_label}, 'FontSize', 10);
    
    % --- Save figure ---
    saveas(fig1, fullfile(output_folder, sprintf('Tmap_%s.png', country_name)));
    
    %% Plot aggregate (mean) control and nostalgia maps
    mean_control = mean(data(:, :, 1), 2);
    mean_nostalgia = mean(data(:, :, 2), 2);
    
    mean_control_img = zeros(size(mask));
    mean_control_img(in_mask) = mean_control;
    
    mean_nostalgia_img = zeros(size(mask));
    mean_nostalgia_img(in_mask) = mean_nostalgia;
    
    Mmean = max(abs([mean_control; mean_nostalgia]));
    if Mmean == 0
        Mmean = 1;
    end
    
    NumCol = 64;
    non_sig = round(0.05 * NumCol);
    hotmap = hot(NumCol - non_sig);
    coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
    hotcoldmap = [
        coldmap
        zeros(2*non_sig,3)
        hotmap
    ];
    
    base = uint8(imread('base.png'));
    base2 = base(10:531, 33:203, :);
    fprintf('Base2 dimensions: %d x %d\n', size(base2, 1), size(base2, 2));
    
    fig2 = figure(99);
    set(gcf, 'Color', [1 1 1]);
    titles = {'Mean Control', 'Mean Nostalgia'};
    
    for c = 1:2
        subplot(1,3,c);
        imagesc(base2);
        axis('off'); axis equal; hold on;
    
        if c == 1
            fh = imagesc(mean_control_img, [-Mmean Mmean]);
        else
            fh = imagesc(mean_nostalgia_img, [-Mmean Mmean]);
        end
        colormap(hotcoldmap);
        set(fh, 'AlphaData', mask);
        title(titles{c}, 'FontSize', 10);
    end
    
    subplot(1,3,3);
    imagesc(ones(size(base2)), [-Mmean Mmean]);
    axis('off');
    colormap(hotcoldmap);
    colorbar;
    title({sprintf('%s: Mean activation', country_name)}, 'FontSize', 10);
    
    % --- Save mean map figure ---
    saveas(fig2, fullfile(output_folder, sprintf('MeanMaps_%s.png', country_name)));
    
end
