%% PCA followed by LDA: Leave-One-Country-Out (LOCO)
clear; close all;

diary_folder = 'LDA';
diary_file = fullfile(diary_folder, 'LOCO_results.txt');
if ~exist(diary_folder, 'dir')
    mkdir(diary_folder);
end
if isfile(diary_file)
    delete(diary_file);
end
diary(diary_file);
diary on;

cfg = read_config();
countries = cfg.countries;   % {'BR','IN','US','SP','JP'}

loco_results = struct();

for i = 1:length(countries)
    test_country   = countries{i};
    train_countries = countries(~strcmp(countries, test_country));

    fprintf('\n>>> Testing on: %s | Training on: %s <<<\n', ...
        test_country, strjoin(train_countries, ', '));

    [X_train, y_train] = load_multiple_countries(cfg.subjects_dir, train_countries);
    [X_test,  y_test]  = load_multiple_countries(cfg.subjects_dir, {test_country});

    num_components = 30;

    warning('off', 'stats:pca:ColRankDefX');
    [coeff, score, ~, ~, ~, mu] = pca(X_train, 'NumComponents', num_components);
    warning('on', 'stats:pca:ColRankDefX');


    X_train_reduced = score;
    X_test_reduced  = (X_test - mu) * coeff;

    lda_model = fitcdiscr(X_train_reduced, y_train, 'DiscrimType', 'linear');
    y_pred = predict(lda_model, X_test_reduced);

    acc = mean(y_pred == y_test) * 100;
    loco_results.(test_country) = acc;
    fprintf('Accuracy for %s: %.2f%%\n', test_country, acc);
    disp(unique(y_pred));
    disp(sum(y_pred == 1));
    disp(sum(y_pred == 0));
    disp(sum(y_train == 1));
    disp(sum(y_train == 0));
end

disp('--- Final LOCO Results ---');
disp(struct2table(loco_results));
diary off;

function [X, y] = load_multiple_countries(subjects_dir, country_list)
    mask = imread('mask.png');
    in_mask = find(mask > 128);
    all_data   = [];
    all_labels = [];

    for c = 1:length(country_list)
        preprocessed_folder = fullfile(subjects_dir, country_list{c}, 'preprocessed');
        mat_files = dir(fullfile(preprocessed_folder, '*_preprocessed.mat'));
        for i = 1:length(mat_files)
            S = load(fullfile(preprocessed_folder, mat_files(i).name));
            if isfield(S, 'nostalgia_avg') && isfield(S, 'control_avg')
                all_data   = [all_data;   S.nostalgia_avg(in_mask)'];
                all_labels = [all_labels; 1];
                all_data   = [all_data;   S.control_avg(in_mask)'];
                all_labels = [all_labels; 0];
            end
        end
    end

    X = all_data;
    y = all_labels;
end