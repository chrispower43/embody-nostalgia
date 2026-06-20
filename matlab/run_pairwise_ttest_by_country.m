function run_pairwise_ttest_by_country(preprocessed_dir)
% RUN_PAIRWISE_TTEST_BY_COUNTRY - Perform pairwise t-test for preprocessed data
% 
% Usage: run_pairwise_ttest_by_country('./preprocessed/')
%        run_pairwise_ttest_by_country('./subjects/US/preprocessed/')

%% Input validation
if nargin < 1
    error('Please provide the path to preprocessed directory');
end

% Ensure path ends with filesep
if ~endsWith(preprocessed_dir, filesep)
    preprocessed_dir = [preprocessed_dir filesep];
end

% Check if directory exists
if ~exist(preprocessed_dir, 'dir')
    error('Preprocessed directory not found: %s', preprocessed_dir);
end

fprintf('Processing preprocessed directory: %s\n', preprocessed_dir);

%% mask (we consider only pixels inside the mask for multiple comparisons)
if ~exist('mask.png', 'file')
    error('mask.png not found in current directory');
end
mask = imread('mask.png');
in_mask = find(mask > 128); % list of pixels inside the mask
fprintf('Mask dimensions: %d x %d\n', size(mask, 1), size(mask, 2));

%% load all subjects
files = dir([preprocessed_dir '*.mat']); % preprocessed files
NS = length(files);

if NS == 0
    error('No .mat files found in directory: %s', preprocessed_dir);
end

fprintf('Found %d preprocessed files\n', NS);

NC = 2;
data = zeros(length(in_mask), NS, NC); 

% Load data from all subjects
for s = 1:NS
    try
        loaded_data = load([preprocessed_dir files(s).name]); % loads control_avg and nostalgia_avg
        % Store the masked data for both conditions
        data(:, s, 1) = loaded_data.control_avg(in_mask);
        data(:, s, 2) = loaded_data.nostalgia_avg(in_mask);
    catch ME
        fprintf('Warning: Could not load file %s. Error: %s\n', files(s).name, ME.message);
        continue;
    end
end

%% Perform paired t-test between conditions
tdata = zeros(length(in_mask),1);
pdata = zeros(length(in_mask),1);

fprintf('Performing paired t-tests for %d pixels...\n', length(in_mask));

for pix = 1:length(in_mask)
    [H, P, CI, STATS] = ttest(data(pix,:,2), data(pix,:,1)); % paired t-test
    %On each pixel, performs pairwise ttest on vector 
    % [(S1-N),(S2-N),...,] > [(S1-C), (S2-C),...]
    tdata(pix) = STATS.tstat;
    pdata(pix) = P;
end

%% Multiple comparisons correction
alltdata = tdata(:);
alltdata(find(~isfinite(alltdata))) = [];   % remove anomalies

df = NS-1;    % degrees of freedom

P = 1-cdf('T', alltdata, df);  % p values- one-tailed p-value calculation
%P = 2 * (1 - cdf('T', abs(alltdata), df));
% Note: The original MATLAB code uses a one-tailed p-value. It seems like
% it's more conventional to use a two-tailed p-value. 
% https://stats.oarc.ucla.edu/other/mult-pkg/faq/general/faq-what-are-the-differences-between-one-tailed-and-two-tailed-tests/
% A one-tailed test is for a directional hypothesis (e.g. x goes up when y goes up and down when y goes down) 
% whereas a two-tailed test is testing just a general relationship (x goes up or down when y goes up for down). 

FDR_val = 0.10;
[pID, pN] = FDR(P, FDR_val);      % BH FDR-> Uses p-data from Matlab Directly
if isempty(pID)
    fprintf("pID empty - no significant results at FDR = %.2f\n", FDR_val);
    tID = [];
else
    tID = icdf('T', 1-pID, df);    % T threshold, indep or pos. correl.
end
tN = icdf('T', 1-pN, df);      % T threshold, no correl. assumptions

fprintf('FDR = %.2f\n', FDR_val)
fprintf('Min p = %.5f, Max p = %.5f\n', min(P), max(P));
if ~isempty(pID)
    fprintf('FDR threshold pID = %g\n', pID);
end
fprintf('df = %d, n_pixels = %d\n', df, length(P));

%% Quick scan of FDR thresholds for diagnostic purposes
% Assumes variables P (vector of p-values) and df (degrees of freedom) already exist

fprintf('\n=== FDR diagnostic scan ===\n');
fprintf('Number of pixels: %d\n', length(P));
fprintf('Min p = %.5g | Max p = %.5g\n', min(P), max(P));

% Range of FDR q-values to test
qvals = [0.01 0.02 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.5];
results = zeros(length(qvals), 2); % store [q, pID]

for i = 1:length(qvals)
    q = qvals(i);
    [pID, pN] = FDR(P, q);
    if isempty(pID)
        results(i,:) = [q, NaN];
        fprintf('q = %.2f --> no surviving pixels (pID empty), th = 3\n', q);
    else
        results(i,:) = [q, pID];
        fprintf('q = %.2f --> pID = %.5f, th = %.2f\n', q, pID, icdf('T', 1-pID, df));
    end
end

% Display summary table
fprintf('\n=== Summary ===\n');
T = array2table(results, 'VariableNames', {'FDR_q', 'pID'});
disp(T);

%% Plot T-maps (Control vs Nostalgia)
M = max(abs(tdata)); % max range for colorbar
if M==0
    fprintf("Warning: M=0, no variation in t-data\n");
    M=1;
end

fprintf("M = %.2f\n", M)
NumCol = 64;

% pick threshold (use FDR-corrected if available, otherwise fallback)
if isempty(tID)
    fprintf('Using uncorrected threshold t = 3\n');
    th = 3;
else
    th = tID;
end
fprintf("th = %.2f\n", th)

non_sig = round(th/M*NumCol); % proportion of non-significant colors
hotmap = hot(NumCol - non_sig);
coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
hotcoldmap = [
    coldmap
    zeros(2*non_sig,3)
    hotmap
];

% reshape t-values into image space
tvals_for_plot = zeros(size(mask));
tvals_for_plot(in_mask) = tdata;
tvals_for_plot(~isfinite(tvals_for_plot)) = 0; % clean NaNs/Infs

% load a base image to overlay results on
if ~exist('base.png', 'file')
    error('base.png not found in current directory');
end
base = uint8(imread('base.png'));
base2 = base(10:531, 33:203, :); % crop to match your region of interest
fprintf('Base2 dimensions: %d x %d\n', size(base2, 1), size(base2, 2));

% Extract country name from path (gets the immediate parent directory name)
[parent_path, country_name] = fileparts(preprocessed_dir);
if strcmp(country_name, 'preprocessed')
    % If we're in a preprocessed subdirectory, go up one more level
    [~, country_name] = fileparts(parent_path);
end

% plot setup
figure('Name', sprintf('T-map - %s', country_name), 'NumberTitle', 'off');
set(gcf, 'Color', [1 1 1]);
subplot(1,2,1);
imagesc(base2);
axis('off');
axis equal;

title(sprintf('%s: Nostalgia > Control (t-map) - %d subjects', country_name, NS), 'FontSize', 10);
hold on;

% overlay the t-values with transparency from mask
fh = imagesc(tvals_for_plot, [-M M]);
colormap(hotcoldmap);
set(fh, 'AlphaData', mask);

% add colorbar
subplot(1,2,2);
fh2 = imagesc(ones(size(base2)), [-M M]);
axis('off');
colormap(hotcoldmap);
colorbar;
title('T-statistic', 'FontSize', 10);

%% Plot aggregate (mean) control and nostalgia maps (signed data)
mean_control = mean(data(:, :, 1), 2);
mean_nostalgia = mean(data(:, :, 2), 2);

mean_control_img = zeros(size(mask));
mean_control_img(in_mask) = mean_control;

mean_nostalgia_img = zeros(size(mask));
mean_nostalgia_img(in_mask) = mean_nostalgia;

% Determine symmetric color scale based on max absolute value
Mmean = max(abs([mean_control; mean_nostalgia]));
if Mmean == 0
    Mmean = 1;
end

% Build diverging hot–cold colormap (same as t-map)
NumCol = 64;
non_sig = round(0.05 * NumCol); % small neutral gap near zero
hotmap = hot(NumCol - non_sig);
coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
hotcoldmap = [
    coldmap
    zeros(2*non_sig,3)
    hotmap
];

base = uint8(imread('base.png'));
base2 = base(10:531, 33:203, :); % crop as before
fprintf('Base2 dimensions: %d x %d\n', size(base2, 1), size(base2, 2));

figure('Name', sprintf('Mean Maps - %s', country_name), 'NumberTitle', 'off');
set(gcf, 'Color', [1 1 1]);

% Extract country name from path (gets the immediate parent directory name)
titles = {sprintf('%s: Mean Control', country_name), sprintf('%s: Mean Nostalgia', country_name)};

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

% Shared colorbar
subplot(1,3,3);
imagesc(ones(size(base2)), [-Mmean Mmean]);
axis('off');
colormap(hotcoldmap);
colorbar;
title('Mean activation', 'FontSize', 10);

fprintf('\nAnalysis completed successfully for directory: %s\n', preprocessed_dir);
fprintf('Total subjects processed: %d\n', NS);

end