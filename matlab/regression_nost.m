%% PCA + Regression (Nostalgia trials only)
clear all
close all

cfg = read_config();

pictures_dir = cfg.pic_regression;
if ~exist(pictures_dir, 'dir')
    mkdir(pictures_dir);
    fprintf('Created directory: %s\n', pictures_dir);
end

mask    = imread('mask.png');
in_mask = find(mask > 128);
fprintf('Mask dimensions: %d x %d\n', size(mask,1), size(mask,2));

preprocessed_folder = fullfile(cfg.subjects_dir, 'all', 'unfiltered', filesep);
mat_files = dir(fullfile(preprocessed_folder, '*_preprocessed.mat'));
NS        = length(mat_files);

% ── Load survey CSV ───────────────────────────────────────────
if exist(cfg.regression_csv, 'file')
    combined_data = readtable(cfg.regression_csv);
    fprintf('Loaded %s with %d subjects\n', cfg.regression_csv, height(combined_data));
else
    error('Regression CSV not found: %s', cfg.regression_csv);
end

% ── Count trials ─────────────────────────────────────────────
total_trials    = 0;
trial_info      = struct();
missing_subjects = {};
missing_columns  = {};

for i = 1:NS
    file_path    = fullfile(preprocessed_folder, mat_files(i).name);
    [~,filename] = fileparts(mat_files(i).name);
    subject_name = strrep(filename, '_preprocessed', '');
    data_i       = load(file_path);
    var_names    = fieldnames(data_i);

    for j = 1:length(var_names)
        var_name = var_names{j};
        if ~isempty(regexp(var_name, '^Nost\d+$', 'once')) && ...
           isempty(strfind(var_name, 'avg'))

            total_trials = total_trials + 1;
            trial_info(total_trials).file_index   = i;
            trial_info(total_trials).subject_name = subject_name;
            trial_info(total_trials).var_name     = var_name;
            trial_info(total_trials).condition    = var_name(1:4);
            trial_info(total_trials).trial_number = str2double(var_name(5:end));

            subject_idx = find(strcmp(combined_data.ID, subject_name));
            if ~isempty(subject_idx)
                col_prefix  = ['N' var_name(5:end)];
                pos_col     = [col_prefix '_pos'];
                neg_col     = [col_prefix '_neg'];

                if ismember(pos_col, combined_data.Properties.VariableNames)
                    trial_info(total_trials).pos_value = combined_data.(pos_col)(subject_idx);
                else
                    trial_info(total_trials).pos_value = NaN;
                    missing_columns{end+1} = struct('subject',subject_name,'trial',var_name,'column',pos_col);
                end
                if ismember(neg_col, combined_data.Properties.VariableNames)
                    trial_info(total_trials).neg_value = combined_data.(neg_col)(subject_idx);
                else
                    trial_info(total_trials).neg_value = NaN;
                    missing_columns{end+1} = struct('subject',subject_name,'trial',var_name,'column',neg_col);
                end
            else
                trial_info(total_trials).pos_value = NaN;
                trial_info(total_trials).neg_value = NaN;
                missing_subjects{end+1} = subject_name;
            end
        end
    end
end

fprintf('Total nostalgia trials: %d  |  Files: %d\n', total_trials, NS);

% ── Load pixel data for nostalgia trials ─────────────────────
data     = zeros(length(in_mask), total_trials);
trial_counter = 1;
for i = 1:NS
    ld        = load(fullfile(preprocessed_folder, mat_files(i).name));
    var_names = fieldnames(ld);
    for j = 1:length(var_names)
        var_name = var_names{j};
        if ~isempty(regexp(var_name, '^Nost\d+$', 'once')) && ...
           isempty(strfind(var_name, 'avg'))
            data(:, trial_counter) = ld.(var_name)(in_mask);
            trial_counter = trial_counter + 1;
        end
    end
end

pos_values = [trial_info.pos_value];
neg_values = [trial_info.neg_value];

% ── PCA ──────────────────────────────────────────────────────
num_components = 30;
[coeff, score, ~, ~, explained] = pca(data', 'NumComponents', num_components);
fprintf('PC1 = %.1f%%  PC2 = %.1f%%  PC3 = %.1f%%\n', explained(1), explained(2), explained(3));

% ── Regression ───────────────────────────────────────────────
min_values    = min(pos_values, neg_values);
griffin_values = (pos_values+neg_values)/2 + abs(pos_values-neg_values);

pos_values    = pos_values    - mean(pos_values,    'omitnan');
neg_values    = neg_values    - mean(neg_values,    'omitnan');
min_values    = min_values    - mean(min_values,    'omitnan');
griffin_values = griffin_values - mean(griffin_values,'omitnan');

pos_reg     = fitlm(score, pos_values);
neg_reg     = fitlm(score, neg_values);
min_reg     = fitlm(score, min_values);
griffin_reg = fitlm(score, griffin_values);

fprintf('\nR² — Pos: %.3f  Neg: %.3f  Min: %.3f  Griffin: %.3f\n', ...
    pos_reg.Rsquared.Adjusted, neg_reg.Rsquared.Adjusted, ...
    min_reg.Rsquared.Adjusted, griffin_reg.Rsquared.Adjusted);

% ── Colormap ─────────────────────────────────────────────────
M      = 0.05;
NumCol = 64;
hotmap = hot(NumCol);
coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
hotcoldmap = [coldmap; hotmap];

% ── PCA overview figure ───────────────────────────────────────
fig_pca = figure;
subplot(1,2,1); plot(score(:,1), score(:,2), 'o');
xlabel('PC1'); ylabel('PC2'); title('Nostalgia trials in PCA space');
subplot(1,2,2); bar(explained(1:min(10,num_components)));
xlabel('PC'); ylabel('Variance (%)'); title('Variance explained');
saveas(fig_pca, fullfile(pictures_dir, [cfg.pic_prefix 'pca_overview.png']));

% ── Map regression weights back to pixel space ────────────────
beta_pos     = pos_reg.Coefficients.Estimate(2:end);
beta_neg     = neg_reg.Coefficients.Estimate(2:end);
beta_min     = min_reg.Coefficients.Estimate(2:end);
beta_griffin = griffin_reg.Coefficients.Estimate(2:end);

pixel_beta_pos     = coeff * beta_pos;
pixel_beta_neg     = coeff * beta_neg;
pixel_beta_min     = coeff * beta_min;
pixel_beta_griffin = coeff * beta_griffin;

function img = make_img(mask, in_mask, vals)
    img = nan(size(mask)); img(in_mask) = vals;
end

pos_img     = make_img(mask, in_mask, pixel_beta_pos);
neg_img     = make_img(mask, in_mask, pixel_beta_neg);
min_img     = make_img(mask, in_mask, pixel_beta_min);
griffin_img = make_img(mask, in_mask, pixel_beta_griffin);

fig_reg = figure;
subplot(2,2,1); imagesc(pos_img,[-M M]); axis image off; colormap(hotcoldmap); colorbar; title('Positive (pixel)');
subplot(2,2,2); imagesc(neg_img,[-M M]); axis image off; colormap(hotcoldmap); colorbar; title('Negative (pixel)');
subplot(2,2,3); imagesc(min_img,[-M M]); axis image off; colormap(hotcoldmap); colorbar; title('Min (pixel)');
subplot(2,2,4); imagesc(griffin_img,[-M M]); axis image off; colormap(hotcoldmap); colorbar; title('Griffin (pixel)');
saveas(fig_reg, fullfile(pictures_dir, [cfg.pic_prefix 'regression_maps.png']));

% ── PC maps ──────────────────────────────────────────────────
fig_pc = figure;
for k = 1:6
    pc_img = nan(size(mask)); pc_img(in_mask) = coeff(:,k);
    subplot(2,3,k); imagesc(pc_img,[-M M]); axis image off;
    colormap(hotcoldmap); colorbar; title(sprintf('PC%d',k));
end
saveas(fig_pc, fullfile(pictures_dir, [cfg.pic_prefix 'pc_maps.png']));

fprintf('\nAll figures saved to: %s\n', pictures_dir);