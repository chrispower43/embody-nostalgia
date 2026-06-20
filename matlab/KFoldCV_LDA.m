%% PCA followed by LDA: classify average Control vs. average Nostalgia maps
% Each participant contributes two samples: control_avg and nostalgia_avg

clear 
close all

countries = {'US'}; 
%countries = {'US','JP', 'IN', 'BR', 'SP'};
for i = 1:length(countries)
    subdir = countries{i};
    run_LDA_by_group(['final&new_subjects/' subdir], subdir);
end

function run_LDA_by_group(basepath, country)
    %% Mask (consider only pixels inside mask)
    mask = imread('mask.png');
    in_mask = find(mask > 128); 
    
    %% Load file list
    preprocessed_folder = [basepath '/preprocessed/'];
    mat_files = dir(fullfile(preprocessed_folder, '*_preprocessed.mat'));
    NS = length(mat_files);
    
    %% Prepare data arrays
    total_samples = NS * 2;
    data = zeros(length(in_mask), total_samples);
    labels = zeros(total_samples, 1); 
    sample_counter = 1;
    
    for i = 1:NS
        file_path = fullfile(preprocessed_folder, mat_files(i).name);
        S = load(file_path);
        if isfield(S, 'nostalgia_avg') && isfield(S, 'control_avg')
            data(:, sample_counter) = S.nostalgia_avg(in_mask);
            labels(sample_counter) = 1;
            sample_counter = sample_counter + 1;
            
            data(:, sample_counter) = S.control_avg(in_mask);
            labels(sample_counter) = 0;
            sample_counter = sample_counter + 1;
        end
    end
    
    % Transpose data so rows are samples and columns are pixels
    X_all = data'; 
    num_components = 30;

    %% ===============================
    %       5-FOLD CROSS-VALIDATION
    % ===============================
    K = 5;
    cvp = cvpartition(labels, 'KFold', K);
    fold_acc = zeros(K, 1);
    
    fprintf('\n === %s %d-Fold CV (Leakage Protected) ===\n', country, K);
    
    for fold = 1:K
        train_idx = training(cvp, fold);
        test_idx  = test(cvp, fold);
        
        % 1. Split RAW data
        X_train_raw = X_all(train_idx, :);
        y_train     = labels(train_idx);
        X_test_raw  = X_all(test_idx, :);
        y_test      = labels(test_idx);
        
        % 2. PCA on TRAINING data only
        % 'mu' is the mean of the training data columns
        [coeff, score, ~, ~, ~, mu] = pca(X_train_raw, 'NumComponents', num_components);
        X_train_reduced = score; 
        
        % 3. Project TEST data using Training Coefficients and Mean
        % Important: We subtract the training mean (mu) from the test data 
        % and multiply by the training coefficients (coeff).
        X_test_centered = X_test_raw - mu;
        X_test_reduced  = X_test_centered * coeff;
        
        % 4. Train LDA
        lda_model = fitcdiscr(X_train_reduced, y_train, 'DiscrimType', 'linear');
        
        % 5. Predict and Evaluate
        y_pred = predict(lda_model, X_test_reduced);
        fold_acc(fold) = mean(y_pred == y_test);
        
        fprintf('  Fold %d: accuracy = %.2f%%\n', fold, fold_acc(fold) * 100);
    end
    
    mean_cv_acc = mean(fold_acc);
    fprintf('%s: Mean 5-fold CV accuracy: %.2f%%\n', country, mean_cv_acc * 100);
    fprintf('===============================\n');
end