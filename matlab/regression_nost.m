%% PCA followed by Regression (Nostalgia Only)
% for a set of preprocessed subjects (modified for averaged conditions and nostalgia trials only)

clear all
close all

%% Create pictures directory if it doesn't exist
pictures_dir = './pictures/regression';
if ~exist(pictures_dir, 'dir')
    mkdir(pictures_dir);
    fprintf('Created directory: %s\n', pictures_dir);
end

%% mask (we consider only pixels inside the mask for multiple comparisons)
mask = imread('mask.png');
in_mask = find(mask > 128); % list of pixels inside the mask
fprintf('Mask dimensions: %d x %d\n', size(mask, 1), size(mask, 2));

% First, count total trials and get file information
preprocessed_folder = './final&new_subjects/all/unfiltered/';
mat_files = dir(fullfile(preprocessed_folder, '*_preprocessed.mat'));
NS = length(mat_files);

% Load the combined_data.csv file
csv_file_path = './regression_all.csv';
if exist(csv_file_path, 'file')
    combined_data = readtable(csv_file_path);
    fprintf('Loaded %s with %d subjects\n', csv_file_path, height(combined_data));
else
    error('combined_data.csv not found at: %s', csv_file_path);
end

% Count total trials first (NOSTALGIA TRIALS ONLY)
total_trials = 0;
trial_info = struct(); % To store information about trials

% Initialize lists to track missing data
missing_subjects = {};
missing_columns = {};

for i = 1:NS
    file_path = fullfile(preprocessed_folder, mat_files(i).name);
    
    % Extract subject name from filename (remove '_preprocessed.mat')
    [~, filename, ~] = fileparts(mat_files(i).name);
    subject_name = strrep(filename, '_preprocessed', '');
    
    data = load(file_path);
    var_names = fieldnames(data);
    
    for j = 1:length(var_names)
        var_name = var_names{j};
        
        % MODIFIED: Check if variable name matches NOSTALGIA trial pattern only and exclude averages
        if ~isempty(regexp(var_name, '^Nost\d+$', 'once')) && ...
           isempty(strfind(var_name, 'avg'))
            total_trials = total_trials + 1;
            trial_info(total_trials).file_index = i;
            trial_info(total_trials).subject_name = subject_name;
            trial_info(total_trials).var_name = var_name;
            trial_info(total_trials).condition = var_name(1:4); % 'Nost'
            trial_info(total_trials).trial_number = str2double(var_name(5:end));
            
            % Extract positive and negative data from combined_data
            % Find the row in combined_data for this subject
            subject_idx = find(strcmp(combined_data.ID, subject_name));
            
            if ~isempty(subject_idx)
                % Create column name based on condition and trial number
                % For nostalgia trials: 'Nost1' becomes 'N1', 'Nost2' becomes 'N2', etc.
                condition_short = 'N'; % Always 'N' for nostalgia trials
                trial_num = var_name(5:end); % trial number
                col_prefix = [condition_short trial_num];
                
                % Get positive and negative values
                pos_col_name = [col_prefix '_pos'];
                neg_col_name = [col_prefix '_neg'];
                
                if ismember(pos_col_name, combined_data.Properties.VariableNames)
                    trial_info(total_trials).pos_value = combined_data.(pos_col_name)(subject_idx);
                else
                    trial_info(total_trials).pos_value = NaN;
                    missing_columns{end+1} = struct('subject', subject_name, 'trial', var_name, 'column', pos_col_name);
                    fprintf('Warning: Column %s not found for subject %s, trial %s\n', pos_col_name, subject_name, var_name);
                end
                
                if ismember(neg_col_name, combined_data.Properties.VariableNames)
                    trial_info(total_trials).neg_value = combined_data.(neg_col_name)(subject_idx);
                else
                    trial_info(total_trials).neg_value = NaN;
                    missing_columns{end+1} = struct('subject', subject_name, 'trial', var_name, 'column', neg_col_name);
                    fprintf('Warning: Column %s not found for subject %s, trial %s\n', neg_col_name, subject_name, var_name);
                end
            else
                trial_info(total_trials).pos_value = NaN;
                trial_info(total_trials).neg_value = NaN;
                missing_subjects{end+1} = subject_name;
                fprintf('Warning: Subject %s not found in combined_data.csv\n', subject_name);
            end
        end
    end
end

fprintf('Total number of NOSTALGIA trials: %d\n', total_trials);
fprintf('Number of files: %d\n', NS);

% Now load all NOSTALGIA trial data
data = zeros(length(in_mask), total_trials);
trial_counter = 1;

for i = 1:NS
    file_path = fullfile(preprocessed_folder, mat_files(i).name);
    loaded_data = load(file_path);
    
    var_names = fieldnames(loaded_data);
    
    for j = 1:length(var_names)
        var_name = var_names{j};
        
        % MODIFIED: Check if variable name matches NOSTALGIA trial pattern only and exclude averages
        if ~isempty(regexp(var_name, '^Nost\d+$', 'once')) && ...
           isempty(strfind(var_name, 'avg'))
            
            % Extract the trial data and apply mask
            trial_data = loaded_data.(var_name);
            data(:, trial_counter) = trial_data(in_mask);
            
            trial_counter = trial_counter + 1;
        end
    end
end

% Optional: Create condition labels and subject labels for easy reference
condition_labels = cell(1, total_trials);
subject_labels = cell(1, total_trials);
pos_values = zeros(1, total_trials);
neg_values = zeros(1, total_trials);

for t = 1:total_trials
    condition_labels{t} = trial_info(t).condition;
    subject_labels{t} = trial_info(t).subject_name;
    pos_values(t) = trial_info(t).pos_value;
    neg_values(t) = trial_info(t).neg_value;
end

fprintf('Successfully loaded %d NOSTALGIA trials\n', trial_counter-1);

% Display some trial information with positive/negative values
fprintf('\nFirst few NOSTALGIA trials info:\n');
for t = 1:min(5, total_trials)
    fprintf('Trial %d: Subject %s, Condition %s, Variable %s, Pos: %d, Neg: %d\n', ...
        t, trial_info(t).subject_name, trial_info(t).condition, trial_info(t).var_name, ...
        trial_info(t).pos_value, trial_info(t).neg_value);
end

% Summary of data availability
valid_pos = sum(~isnan(pos_values));
valid_neg = sum(~isnan(neg_values));
fprintf('\nData summary (NOSTALGIA trials only):\n');
fprintf('Trials with valid positive data: %d/%d (%.1f%%)\n', valid_pos, total_trials, valid_pos/total_trials*100);
fprintf('Trials with valid negative data: %d/%d (%.1f%%)\n', valid_neg, total_trials, valid_neg/total_trials*100);

% Detailed report of missing data
fprintf('\n=== MISSING DATA REPORT (NOSTALGIA TRIALS ONLY) ===\n');

% Report missing subjects
if ~isempty(missing_subjects)
    missing_subjects_unique = unique(missing_subjects);
    fprintf('\nSubjects not found in CSV (%d unique subjects):\n', length(missing_subjects_unique));
    for s = 1:length(missing_subjects_unique)
        subject = missing_subjects_unique{s};
        % Count how many trials are affected for this subject
        trial_count = sum(strcmp({trial_info.subject_name}, subject));
        fprintf('  %s (%d trials affected)\n', subject, trial_count);
        
        % List specific trials for this subject
        subject_trials = find(strcmp({trial_info.subject_name}, subject));
        for st = 1:length(subject_trials)
            trial_idx = subject_trials(st);
            fprintf('    - Trial: %s\n', trial_info(trial_idx).var_name);
        end
    end
else
    fprintf('\nAll subjects found in CSV file.\n');
end

% Report missing columns
if ~isempty(missing_columns)
    fprintf('\nMissing columns in CSV (%d instances):\n', length(missing_columns));
    
    % Group by subject for cleaner reporting
    subjects_with_missing_cols = unique({missing_columns.subject});
    for s = 1:length(subjects_with_missing_cols)
        subject = subjects_with_missing_cols{s};
        subject_missing = missing_columns(strcmp({missing_columns.subject}, subject));
        
        fprintf('  Subject: %s\n', subject);
        for m = 1:length(subject_missing)
            fprintf('    - Trial %s: Column %s missing\n', ...
                subject_missing(m).trial, subject_missing(m).column);
        end
    end
else
    fprintf('\nAll required columns found in CSV file.\n');
end

% List all trials with missing data
fprintf('\nAll NOSTALGIA trials with missing data:\n');
missing_trials = find(isnan(pos_values) | isnan(neg_values));
if ~isempty(missing_trials)
    for mt = 1:length(missing_trials)
        t = missing_trials(mt);
        missing_types = {};
        if isnan(trial_info(t).pos_value), missing_types{end+1} = 'positive'; end
        if isnan(trial_info(t).neg_value), missing_types{end+1} = 'negative'; end
        
        fprintf('  Trial %d: Subject %s, %s - Missing %s data\n', ...
            t, trial_info(t).subject_name, trial_info(t).var_name, ...
            strjoin(missing_types, ' and '));
    end
else
    fprintf('  No NOSTALGIA trials with missing data!\n');
end

% Summary statistics
fprintf('\n=== SUMMARY (NOSTALGIA TRIALS ONLY) ===\n');
fprintf('Total NOSTALGIA trials processed: %d\n', total_trials);
fprintf('NOSTALGIA trials with complete data: %d (%.1f%%)\n', sum(~isnan(pos_values) & ~isnan(neg_values)), ...
    sum(~isnan(pos_values) & ~isnan(neg_values))/total_trials*100);
fprintf('NOSTALGIA trials with any missing data: %d (%.1f%%)\n', length(missing_trials), ...
    length(missing_trials)/total_trials*100);

%% PCA Analysis - Top 30 Dimensions using MATLAB's pca() function

num_components = 30;
[coeff, score, latent, tsquared, explained, mu] = pca(data', 'NumComponents', num_components);

fprintf('Output sizes:\n');
fprintf('  coeff: %d voxels x %d components\n', size(coeff, 1), size(coeff, 2));
fprintf('  score: %d NOSTALGIA trials x %d components\n', size(score, 1), size(score, 2));
fprintf('  latent: %d x %d\n', size(latent, 1), size(latent, 2));
fprintf('  explained: %d x %d\n', size(explained, 1), size(explained, 2));
fprintf('  tsquared: %d x %d\n', size(tsquared, 1), size(tsquared, 2));

% Percentage of total variance explained by each PC
fprintf('PC1 explains %.1f%% of total variance\n', explained(1));
fprintf('PC2 explains %.1f%% of total variance\n', explained(2));
fprintf('PC3 explains %.1f%% of total variance\n', explained(3));
fprintf('PC4 explains %.1f%% of total variance\n', explained(4));
fprintf('PC5 explains %.1f%% of total variance\n', explained(5));
fprintf('PC6 explains %.1f%% of total variance\n', explained(6));

total_captured = sum(explained(:));
fprintf('Total variance explained by 30 PCs: %.0f%% \n', total_captured);

% Hotelling's T-squared - how "weird" each trial is
[abc, outlier_idx] = max(tsquared);
fprintf('NOSTALGIA trial %d is the most extreme in PCA space w/ value %f \n', outlier_idx, abc);

% Simple plot that should work
figure;
subplot(1, 2, 1);
plot(score(:, 1), score(:, 2), 'o');
xlabel('PC1'); ylabel('PC2');
title('NOSTALGIA Trials in PCA Space');

subplot(1, 2, 2);
bar(explained(1:min(10, num_components)));
xlabel('Principal Component');
ylabel('Variance Explained (%)');
title('First 30 Components Variance (NOSTALGIA Trials)');

% Save PCA overview figure
saveas(gcf, fullfile(pictures_dir, 'pca_overview.png'));
fprintf('Saved PCA overview figure to: %s\n', fullfile(pictures_dir, 'pca_overview.png'));

% These are what you use for LDA
data_reduced = score;
pca_coeff = coeff;

%% Starting with positive valence. 

min_values = min(pos_values, neg_values);
griffin_values = (pos_values+neg_values)/2 + abs(pos_values-neg_values);

%mean centering values

pos_values = pos_values - mean(pos_values);
neg_values = neg_values - mean(neg_values);
min_values = min_values - mean(min_values);
griffin_values = griffin_values -mean (griffin_values);


pos_reg = fitlm(score,pos_values);
neg_reg = fitlm(score, neg_values);
min_reg = fitlm(score, min_values);
griffin_reg = fitlm(score, griffin_values);

% Remove pixels that are zero across all trials
% nonzero_rows = any(data ~= 0, 2);
% data_filtered = data(nonzero_rows, :);

% pos_reg = fitlm(data', pos_values);
% neg_reg = fitlm(data', neg_values);
% min_reg = fitlm(data', min_values);

fprintf('\n--- Model Fits (NOSTALGIA TRIALS ONLY) ---\n');
fprintf('Positive: R² = %.3f\n', pos_reg.Rsquared.Adjusted);
fprintf('Negative: R² = %.3f\n', neg_reg.Rsquared.Adjusted);
fprintf('Min valence: R² = %.3f\n', min_reg.Rsquared.Adjusted);
fprintf('Griffin valence: R² = %.3f\n', griffin_reg.Rsquared.Adjusted);

fprintf('\n--- ANOVA Results (NOSTALGIA TRIALS ONLY) ---\n');
fprintf('Positive valence model:\n');
anova(pos_reg, 'summary')
fprintf('Negative valence model:\n');
anova(neg_reg, 'summary')
fprintf('Min valence model:\n');
anova(min_reg, 'summary')
fprintf('Griffin valence model:\n');
anova(griffin_reg, 'summary')


%% Create hot–cold colormap (same logic as your t-maps)
M = 0.05;               % symmetric range for display
NumCol = 64;
non_sig = 0;

hotmap = hot(NumCol - non_sig);
coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);   % RGB flipped
hotcoldmap = [
    coldmap;
    zeros(2 * non_sig, 3);
    hotmap
];

%% PC1 and PC2 maps in pixel space
pc1_map = coeff(:,1);
pc2_map = coeff(:,2);
pc3_map = coeff(:,3);
pc4_map = coeff(:,4);
pc5_map = coeff(:,5);
pc6_map = coeff(:,6);

pc1_img = nan(size(mask));
pc2_img = nan(size(mask));
pc3_img = nan(size(mask));
pc4_img = nan(size(mask));
pc5_img = nan(size(mask));
pc6_img = nan(size(mask));

pc1_img(in_mask) = pc1_map;
pc2_img(in_mask) = pc2_map;
pc3_img(in_mask) = pc3_map;
pc4_img(in_mask) = pc4_map;
pc5_img(in_mask) = pc5_map;
pc6_img(in_mask) = pc6_map;

%% Plot using SAME hot-cold map as t-maps
figure;

subplot(2,3,1);
imagesc(pc1_img, [-M M]); 
axis image off;
colormap(hotcoldmap);
colorbar;
title('PC1');

subplot(2,3,2);
imagesc(pc2_img, [-M M]);
axis image off;
colormap(hotcoldmap);
colorbar;
title('PC2');

subplot(2,3,3);
imagesc(pc3_img, [-M M]); 
axis image off;
colormap(hotcoldmap);
colorbar;
title('PC3');

subplot(2,3,4);
imagesc(pc4_img, [-M M]);
axis image off;
colormap(hotcoldmap);
colorbar;
title('PC4');

subplot(2,3,5);
imagesc(pc5_img, [-M M]); 
axis image off;
colormap(hotcoldmap);
colorbar;
title('PC5');

subplot(2,3,6);
imagesc(pc6_img, [-M M]);
axis image off;
colormap(hotcoldmap);
colorbar;
title('PC6');

% Save PC maps figure
saveas(gcf, fullfile(pictures_dir, 'pc_maps.png'));
fprintf('Saved PC maps figure to: %s\n', fullfile(pictures_dir, 'pc_maps.png'));

%% ------------------------------------------------------------
%% MAP REGRESSION WEIGHTS FROM PCA SPACE BACK INTO PIXEL SPACE
%% ------------------------------------------------------------

fprintf('\n--- Mapping regression weights back to pixel space ---\n');

% Extract regression coefficients from models
% fitlm includes an intercept; we skip it
beta_pos = pos_reg.Coefficients.Estimate(2:end);   % PCs → pos
beta_neg = neg_reg.Coefficients.Estimate(2:end);   % PCs → neg
beta_min = min_reg.Coefficients.Estimate(2:end);   % PCs → min
beta_griffin = griffin_reg.Coefficients.Estimate(2:end);   % PCs → min


% Project regression weights from PC space → pixel space
% pixel_betas = coefficients * PCA_loadings'
%
% coeff is d × PCs, so:
%   pixel_map = coeff * beta_in_PC_space

pixel_beta_pos = coeff * beta_pos;
pixel_beta_neg = coeff * beta_neg;
pixel_beta_min = coeff * beta_min;
pixel_beta_griffin = coeff * beta_griffin;

% Prepare blank images
pos_img = nan(size(mask));
neg_img = nan(size(mask));
min_img = nan(size(mask));
griffin_img = nan(size(mask));

pos_img(in_mask) = pixel_beta_pos;
neg_img(in_mask) = pixel_beta_neg;
min_img(in_mask) = pixel_beta_min;
griffin_img(in_mask) = pixel_beta_griffin;


%% Plot regression → pixel maps
figure;
subplot(2,2,1);
imagesc(pos_img, [-M M]);
axis image off;
colormap(hotcoldmap);
colorbar;
title('Positive regression (pixel space)');

subplot(2,2,2);
imagesc(neg_img, [-M M]);
axis image off;
colormap(hotcoldmap);
colorbar;
title('Negative regression (pixel space)');

subplot(2,2,3);
imagesc(min_img, [-M M]);
axis image off;
colormap(hotcoldmap);
colorbar;
title('Min regression (pixel space)');

subplot(2,2,4);
imagesc(griffin_img, [-M M]);
axis image off;
colormap(hotcoldmap);
colorbar;
title('Griffin regression (pixel space)');

% Save regression maps figure
saveas(gcf, fullfile(pictures_dir, 'regression_maps.png'));
fprintf('Saved regression maps figure to: %s\n', fullfile(pictures_dir, 'regression_maps.png'));

%% ------------------------------------------------------------
%% OPTIONAL: VIEW EACH PC's INDIVIDUAL LINEAR EFFECT IN PIXEL SPACE
%% beta_pos(k)*PC_k  mapped back to voxels
%% ------------------------------------------------------------

num_PCs_to_plot = 6;   % change if you want more
M=0.005;

% Positive regression PC contributions
figure;
for k = 1:num_PCs_to_plot
    subplot(2, ceil(num_PCs_to_plot/2), k);

    pixel_map_k = coeff(:,k) .* beta_pos(k);   % PC's contribution scaled by regression

    img_k = nan(size(mask));
    img_k(in_mask) = pixel_map_k;

    imagesc(img_k, [-M M]);
    axis image off;
    colormap(hotcoldmap);
    colorbar;
    title(sprintf('Pos regression: PC %d contribution', k));
end
saveas(gcf, fullfile(pictures_dir, 'pos_regression_pc_contributions.png'));
fprintf('Saved positive regression PC contributions figure to: %s\n', fullfile(pictures_dir, 'pos_regression_pc_contributions.png'));

% Negative regression PC contributions
figure;
for k = 1:num_PCs_to_plot
    subplot(2, ceil(num_PCs_to_plot/2), k);

    pixel_map_k = coeff(:,k) .* beta_neg(k);   % PC's contribution scaled by regression

    img_k = nan(size(mask));
    img_k(in_mask) = pixel_map_k;

    imagesc(img_k, [-M M]);
    axis image off;
    colormap(hotcoldmap);
    colorbar;
    title(sprintf('Neg regression: PC %d contribution', k));
end
saveas(gcf, fullfile(pictures_dir, 'neg_regression_pc_contributions.png'));
fprintf('Saved negative regression PC contributions figure to: %s\n', fullfile(pictures_dir, 'neg_regression_pc_contributions.png'));

% Min regression PC contributions
figure;
for k = 1:num_PCs_to_plot
    subplot(2, ceil(num_PCs_to_plot/2), k);

    pixel_map_k = coeff(:,k) .* beta_min(k);   % PC's contribution scaled by regression

    img_k = nan(size(mask));
    img_k(in_mask) = pixel_map_k;

    imagesc(img_k, [-M M]);
    axis image off;
    colormap(hotcoldmap);
    colorbar;
    title(sprintf('Min regression: PC %d contribution', k));
end
saveas(gcf, fullfile(pictures_dir, 'min_regression_pc_contributions.png'));
fprintf('Saved min regression PC contributions figure to: %s\n', fullfile(pictures_dir, 'min_regression_pc_contributions.png'));

% Griffin regression PC contributions
figure;
for k = 1:num_PCs_to_plot
    subplot(2, ceil(num_PCs_to_plot/2), k);

    pixel_map_k = coeff(:,k) .* beta_griffin(k);   % PC's contribution scaled by regression

    img_k = nan(size(mask));
    img_k(in_mask) = pixel_map_k;

    imagesc(img_k, [-M M]);
    axis image off;
    colormap(hotcoldmap);
    colorbar;
    title(sprintf('Griffin regression: PC %d contribution', k));
end
saveas(gcf, fullfile(pictures_dir, 'griffin_regression_pc_contributions.png'));
fprintf('Saved griffin regression PC contributions figure to: %s\n', fullfile(pictures_dir, 'griffin_regression_pc_contributions.png'));

fprintf('\nAll figures saved to: %s\n', pictures_dir);