%% PCA followed by LDA: classify average Control vs. average Nostalgia maps
% Each participant contributes two samples: control_avg and nostalgia_avg
clear
close all

cfg = read_config();
countries = [cfg.countries, {'all'}];

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

    % --- First pass: identify participants with BOTH maps present ---
    valid_mask = false(NS, 1);
    for i = 1:NS
        file_path = fullfile(preprocessed_folder, mat_files(i).name);
        S = load(file_path, 'nostalgia_avg', 'control_avg');
        if isfield(S, 'nostalgia_avg') && isfield(S, 'control_avg')
            valid_mask(i) = true;
        else
            fprintf('  Excluding %s: missing nostalgia_avg or control_avg\n', mat_files(i).name);
        end
    end
    valid_idx = find(valid_mask);
    N_valid = length(valid_idx);

    if N_valid < 2
        fprintf('%s: not enough valid participants (%d), skipping.\n', country, N_valid);
        return;
    end

    total_samples = N_valid * 2;
    data = zeros(length(in_mask), total_samples);
    labels = zeros(total_samples, 1);
    participant_id = zeros(total_samples, 1);   % ties each sample back to its participant

    sample_counter = 1;
    for k = 1:N_valid
        i = valid_idx(k);
        file_path = fullfile(preprocessed_folder, mat_files(i).name);
        S = load(file_path, 'nostalgia_avg', 'control_avg');

        data(:, sample_counter) = S.nostalgia_avg(in_mask);
        labels(sample_counter) = 1;
        participant_id(sample_counter) = k;
        sample_counter = sample_counter + 1;

        data(:, sample_counter) = S.control_avg(in_mask);
        labels(sample_counter) = 0;
        participant_id(sample_counter) = k;
        sample_counter = sample_counter + 1;
    end

    X_all = data';
    num_components = 30;
    K = 5;

    % --- Participant-level fold assignment ---
    % Partition over participants (not samples), then propagate each
    % participant's fold to both of their samples so a participant is
    % never split across train/test.
    cvp_participant = cvpartition(N_valid, 'KFold', K);

    fold_acc = zeros(K, 1);
    fprintf('\n === %s %d-Fold CV (Leakage Protected) ===\n', country, K);
    for fold = 1:K
        train_participants = find(training(cvp_participant, fold));
        test_participants  = find(test(cvp_participant, fold));

        train_idx = ismember(participant_id, train_participants);
        test_idx  = ismember(participant_id, test_participants);

        X_train_raw = X_all(train_idx, :);
        y_train     = labels(train_idx);
        X_test_raw  = X_all(test_idx, :);
        y_test      = labels(test_idx);

        [coeff, score, ~, ~, ~, mu] = pca(X_train_raw, 'NumComponents', num_components);
        X_train_reduced = score;
        X_test_reduced  = (X_test_raw - mu) * coeff;

        lda_model = fitcdiscr(X_train_reduced, y_train, 'DiscrimType', 'linear');
        y_pred = predict(lda_model, X_test_reduced);
        fold_acc(fold) = mean(y_pred == y_test);
        fprintf('  Fold %d: accuracy = %.2f%%\n', fold, fold_acc(fold) * 100);
    end

    mean_cv_acc = mean(fold_acc);
    fprintf('%s: Mean 5-fold CV accuracy: %.2f%%\n', country, mean_cv_acc * 100);
    fprintf('===============================\n');
end