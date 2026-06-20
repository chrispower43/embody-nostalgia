%% PCA followed by LDA: classify average Control vs. average Nostalgia maps
% Each participant contributes two samples: control_avg and nostalgia_avg

clear 
close all

%countries = {'all/'}; 
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
    subject_id = zeros(total_samples, 1); % Track which samples belong to which person
    sample_counter = 1;
    
    for i = 1:NS
        file_path = fullfile(preprocessed_folder, mat_files(i).name);
        S = load(file_path);
        if isfield(S, 'nostalgia_avg') && isfield(S, 'control_avg')
            % Subject ID 'i' assigned to both samples
            data(:, sample_counter) = S.nostalgia_avg(in_mask);
            labels(sample_counter) = 1;
            subject_id(sample_counter) = i; 
            sample_counter = sample_counter + 1;
            
            data(:, sample_counter) = S.control_avg(in_mask);
            labels(sample_counter) = 0;
            subject_id(sample_counter) = i;
            sample_counter = sample_counter + 1;
        end
    end
    
    % Transpose data (samples x pixels)
    X_all = data'; 
    num_components = 30;

    %% ==========================================
    %   LEAVE-ONE-SUBJECT-OUT CROSS-VALIDATION
    % ==========================================
    % 'LeaveOut' on subject_id ensures both maps of one person are held out
    cvp = cvpartition(subject_id, 'LeaveOut');
    num_folds = cvp.NumTestSets; 
    fold_acc = zeros(num_folds, 1);
    
    fprintf('\n === %s Leave-One-Subject-Out CV (%d Subjects) ===\n', country, num_folds);
    
    for fold = 1:num_folds
        train_idx = training(cvp, fold);
        test_idx  = test(cvp, fold);
        
        X_train_raw = X_all(train_idx, :);
        y_train     = labels(train_idx);
        X_test_raw  = X_all(test_idx, :);
        y_test      = labels(test_idx);
        
        % 1. PCA on TRAINING data only
        [coeff, score, ~, ~, ~, mu] = pca(X_train_raw, 'NumComponents', num_components);
        X_train_reduced = score; 
        
        % 2. Project TEST data (subject held out) into Training PCA space
        X_test_centered = X_test_raw - mu;
        X_test_reduced  = X_test_centered * coeff;
        
        % 3. Train LDA
        lda_model = fitcdiscr(X_train_reduced, y_train, 'DiscrimType', 'linear');
        
        % 4. Predict
        y_pred = predict(lda_model, X_test_reduced);
        fold_acc(fold) = mean(y_pred == y_test);
    end
    
    mean_cv_acc = mean(fold_acc);
    fprintf('%s: Mean LOSO CV accuracy: %.2f%%\n', country, mean_cv_acc * 100);
    fprintf('==========================================\n');
end