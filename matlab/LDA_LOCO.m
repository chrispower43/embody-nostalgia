%% PCA followed by LDA: Leave-One-Country-Out (LOCO)
% Performs PCA on training data only. Notably. 
clear; close all;

countries = {'US', 'JP', 'IN', 'BR', 'SP'};
base_path = 'final&new_subjects/';
mask_file = 'mask.png';

% Results storage
loco_results = struct();

for i = 1:length(countries)
    test_country = countries{i};
    train_countries = countries(~strcmp(countries, test_country));
    
    fprintf('\n>>> Testing on: %s | Training on: %s <<<\n', ...
        test_country, strjoin(train_countries, ', '));
    
    %% 1. Load Training Data (Aggregated)
    [X_train, y_train] = load_multiple_countries(base_path, train_countries, mask_file);
    
    %% 2. Load Testing Data
    [X_test, y_test] = load_multiple_countries(base_path, {test_country}, mask_file);
    
    %% 3. PCA (Fit on Train, Apply to Test)
    % We calculate the PCA transformation based ONLY on training data
    num_components = 30;
    [coeff, score, ~, ~, explained, mu] = pca(X_train, 'NumComponents', num_components);
    
    X_train_reduced = score;
    
    % Project Test data into the Training PCA space
    % Important: Subtract training mean (mu) and multiply by training coefficients
    X_test_centered = X_test - mu; 
    X_test_reduced = X_test_centered * coeff;
    
    %% 4. Train LDA
    lda_model = fitcdiscr(X_train_reduced, y_train, 'DiscrimType', 'linear');
    
    %% 5. Test LDA
    y_pred = predict(lda_model, X_test_reduced);
    acc = mean(y_pred == y_test) * 100;
    
    loco_results.(test_country) = acc;
    fprintf('Accuracy for %s: %.2f%%\n', test_country, acc);
    disp(unique(y_pred));          % Is it predicting only one class?
    disp(sum(y_pred == 1));        % How many nostalgia predictions?
    disp(sum(y_pred == 0));        % How many control predictions?
    disp(sum(y_train == 1));
    disp(sum(y_train == 0));

end

% Display Final Summary
disp('--- Final LOCO Results ---');
disp(struct2table(loco_results));

%% Helper Function to Load and Mask Data
function [X, y] = load_multiple_countries(basepath, country_list, mask_file)
    mask = imread(mask_file);
    in_mask = find(mask > 128);
    
    all_data = [];
    all_labels = [];
    
    for c = 1:length(country_list)
        subdir = country_list{c};
        preprocessed_folder = fullfile(basepath, subdir, 'preprocessed');
        mat_files = dir(fullfile(preprocessed_folder, '*_preprocessed.mat'));
        
        for i = 1:length(mat_files)
            S = load(fullfile(preprocessed_folder, mat_files(i).name));
            if isfield(S, 'nostalgia_avg') && isfield(S, 'control_avg')
                % Add Nostalgia (Label 1)
                all_data = [all_data; S.nostalgia_avg(in_mask)'];
                all_labels = [all_labels; 1];
                % Add Control (Label 0)
                all_data = [all_data; S.control_avg(in_mask)'];
                all_labels = [all_labels; 0];
            end
        end
    end
    X = all_data;
    y = all_labels;
end