%% Pairwise ttest
% for a set of preprocessed subjects (modified for averaged conditions)

clear all
close all

%% mask (we consider only pixels inside the mask for multiple comparisons)
mask = imread('mask.png');
in_mask = find(mask > 128); % list of pixels inside the mask

%% load all subjects
basepath = './filter1_subjects/all/preprocessed/';
files = dir([basepath '*.mat']); % preprocessed files
NS = length(files);
NC = 2;
data = zeros(length(in_mask), NS, NC); 

for s = 1:NS
    %loaded_data= load([basepath files(s).name])
    loaded_data=load([basepath files(s).name]); % loads control_avg and nostalgia_avg
     % Store the masked data for both conditions
    data(:, s, 1) = loaded_data.control_avg(in_mask);
    data(:, s, 2) = loaded_data.nostalgia_avg(in_mask);
end

%% Perform paired t-test between conditions
tdata = zeros(length(in_mask),1);
pdata = zeros(length(in_mask),1);

% % This is incorrect:
% control_avg = mean(data(:,:,1),1);
% nostalgia_avg = mean(data(:,:,2),1);
% [H, P, CI, STATS] = ttest(nostalgia_avg, control_avg); % paired t-test

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

FDR_val= 0.05;
[pID, pN] = FDR(P, FDR_val);      % BH FDR
if isempty(pID)
    disp("pID empty");
    tID = [];
else
    tID = icdf('T', 1-pID, df);    % T threshold, indep or pos. correl.
end
tN = icdf('T', 1-pN, df);      % T threshold, no correl. assumptions

fprintf('FDR = %f\n', FDR_val)
fprintf('Min p = %.5f, Max p = %.5f\n', min(P), max(P));
fprintf('FDR threshold pID = %g\n', pID);
fprintf('df = %d, n_pixels = %d\n', df, length(P));

% %% Quick scan of FDR thresholds for diagnostic purposes
% % Assumes variables P (vector of p-values) and df (degrees of freedom) already exist
% 
% fprintf('\n=== FDR diagnostic scan ===\n');
% fprintf('Number of pixels: %d\n', length(P));
% fprintf('Min p = %.5g | Max p = %.5g\n', min(P), max(P));
% 
% % Range of FDR q-values to test
% qvals = [0.01 0.02 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.5];
% results = zeros(length(qvals), 2); % store [q, pID]
% 
% for i = 1:length(qvals)
%     q = qvals(i);
%     [pID, pN] = FDR(P, q);
%     if isempty(pID)
%         results(i,:) = [q, NaN];
%         fprintf('q = %.2f --> no surviving pixels (pID empty), th = 3\n', q);
%     else
%         results(i,:) = [q, pID];
%         fprintf('q = %.2f --> pID = %.5f, th = %.2f\n', q, pID, icdf('T', 1-pID, df));
%     end
% end
% 
% % Display summary table
% fprintf('\n=== Summary ===\n');
% T = array2table(results, 'VariableNames', {'FDR_q', 'pID'});
% disp(T);
% 
% % % Optional: plot for a visual look
% % figure;
% % plot(qvals, results(:,2), 'o-', 'LineWidth', 1.5);
% % xlabel('FDR level q');
% % ylabel('pID threshold (smaller = stricter)');
% % title('FDR scan: pID vs. q');
% % grid on;


%% Plot T-maps (Control vs Nostalgia)
M = max(abs(tdata)); % max range for colorbar
if M==0
    disp("M=0");
    M=1;
end

fprintf("M = %d\n", M)
NumCol = 64;

% pick threshold (use FDR-corrected if available, otherwise fallback)
if isempty(tID)
    disp('Using uncorrected threshold t = 3');
    th = 3;
else
    th = tID;
end
fprintf("th = %d\n", th)


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
base = uint8(imread('base.png'));
base2 = base(10:531, 33:203, :); % crop to match your region of interest
fprintf('Base2 dimensions: %d x %d\n', size(base2, 1), size(base2, 2));

% plot setup
figure(100);
set(gcf, 'Color', [1 1 1]);
subplot(1,2,1);
imagesc(base2);
axis('off');
axis equal;
title('Nostalgia > Control (t-map)', 'FontSize', 10);
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

figure(99);
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

% Shared colorbar
subplot(1,3,3);
imagesc(ones(size(base2)), [-Mmean Mmean]);
axis('off');
colormap(hotcoldmap);
colorbar;
title('Mean activation', 'FontSize', 10);



% 
% % plotting
% plotcols = 2; %set as desired
% plotrows = ceil((NC+1)/plotcols); % number of rows is equal to number of conditions+1 (for the colorbar)
% base=uint8(imread('base.png'));
% base2=base(10:531,33:203,:); % single image base
% labels={
% 'Control'
% 'Nostalgia'
% };
% 
% for n=1:2
%     figure(100)
%     subplot(plotrows,plotcols,n)
%     imagesc(base2);
%     axis('off');
%     set(gcf,'Color',[1 1 1]);
%     hold on;
%     over2=tvals_for_plot(:,:,n);
%     fh=imagesc(over2,[-M,M]);
%     axis('off');
%     axis equal
%     colormap(hotcoldmap);
%     set(fh,'AlphaData',mask)
%     title(labels(n),'FontSize',10)
%     if(n==2)
%         subplot(plotrows,plotcols,n+1)
%         fh=imagesc(ones(size(base2)),[-M,M]);
%         axis('off');
%         colorbar;
%     end
% end

