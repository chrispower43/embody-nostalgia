%% PCA followed by LDA: classify average Control vs. average Nostalgia maps
% Each participant contributes two samples: control_avg and nostalgia_avg
clear
close all

cfg = read_config();
countries = [cfg.countries, {'all'}];   % {'BR','IN','US','SP','JP','all'}

for i = 1:length(countries)
    subdir = countries{i};
    run_LDA_by_group(fullfile(cfg.subjects_dir, subdir), subdir);
end

function run_LDA_by_group(basepath, country)
    mask = imread('mask.png');
    in_mask = find(mask > 128);

    preprocessed_folder = fullfile(basepath, 'preprocessed', filesep);
    mat_files = dir(fullfile(preprocessed_folder, '*_preprocessed.mat'));
    NS = length(mat_files);

    total_samples = NS * 2;
    data = zeros(length(in_mask), total_samples);
    labels = zeros(total_samples, 1);
    subject_id = zeros(total_samples, 1);
    sample_counter = 1;

    for i = 1:NS
        file_path = fullfile(preprocessed_folder, mat_files(i).name);
        S = load(file_path);
        if isfield(S, 'nostalgia_avg') && isfield(S, 'control_avg')
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

    X_all = data';
    num_components = 30;

    unique_subjects = unique(subject_id);
    NS_unique = length(unique_subjects);
    fold_acc = zeros(NS_unique, 1);
    fprintf('\n === %s Leave-One-Subject-Out CV (%d Subjects) ===\n', country, NS_unique);
    
    for fold = 1:NS_unique
        test_subject = unique_subjects(fold);
        test_idx  = subject_id == test_subject;
        train_idx = subject_id ~= test_subject;
    
        X_train_raw = X_all(train_idx, :);
        y_train     = labels(train_idx);
        X_test_raw  = X_all(test_idx, :);
        y_test      = labels(test_idx);
    
        warning('off', 'stats:pca:ColRankDefX');
        [coeff, score, ~, ~, ~, mu] = pca(X_train_raw, 'NumComponents', num_components);
        warning('on', 'stats:pca:ColRankDefX');
    
        X_train_reduced = score;
        X_test_reduced  = (X_test_raw - mu) * coeff;
    
        lda_model = fitcdiscr(X_train_reduced, y_train, 'DiscrimType', 'linear');
        y_pred = predict(lda_model, X_test_reduced);
        fold_acc(fold) = mean(y_pred == y_test);
    end

    mean_cv_acc = mean(fold_acc);
    fprintf('%s: Mean LOSO CV accuracy: %.2f%%\n', country, mean_cv_acc * 100);
    fprintf('==========================================\n');
end