%% plot_all_nostalgia.m
%  Paginated per-subject painting browser.
%  Subjects are sorted by survey duration (ascending) using durations
%  read from combined_data_all.csv (set in config.toml).
%
%  To change the cohort or output folder, edit config.toml — no changes
%  needed here.

clear
close all

cfg = read_config();

% Override countries here if you want to inspect a subset, e.g. {'JP'}
% Otherwise cfg.countries runs all five.
countries = cfg.countries;
% countries = {'JP'};

for i = 1:length(countries)
    country  = countries{i};
    basepath = fullfile(cfg.subjects_dir, country, 'subjects');
    plot_all(basepath, country, cfg.combined_csv, cfg.pic_individual, 5, false);
end


%% =========================================================
function plot_all(basepath, country, combined_csv, pic_individual, subjects_per_page, save_only)
%PLOT_ALL  Paginated layout of nostalgia/control body maps for one country.
%
%   basepath          path to the <cohort>/<country>/subjects/ folder
%   country           country code string, e.g. 'US'
%   combined_csv      path to combined_data_all.csv (for durations)
%   pic_individual    base output folder from cfg.pic_individual
%   subjects_per_page number of subjects per figure page  (default 5)
%   save_only         if true, figures are saved without being displayed

    close all

    if nargin < 5, subjects_per_page = 5; end
    if nargin < 6, save_only = true;      end

    % Output folder: pictures/individual/<country>/  (or with prefix)
    output_folder = fullfile(pic_individual, country);
    if ~exist(output_folder, 'dir')
        mkdir(output_folder);
    else
        delete(fullfile(output_folder, '*.png'));
        fprintf('Cleared existing pictures in %s\n', output_folder);
    end

    % ── Load subject folders ───────────────────────────────────────────────
    subject_entries = dir(basepath);
    subject_entries = subject_entries(~startsWith({subject_entries.name}, '.'));
    numSubjects     = length(subject_entries);

    if numSubjects == 0
        fprintf('No subjects found in %s — skipping %s.\n', basepath, country);
        return;
    end

    % ── Load durations from combined_data_all.csv ──────────────────────────
    % Duration column was renamed from "Duration (in seconds)" by
    % build_combined_data.py — it is simply "Duration" in the combined CSV.
    if exist(combined_csv, 'file')
        csv_data      = readtable(combined_csv, 'VariableNamingRule', 'preserve');
        csv_ids       = string(csv_data.ID);
        csv_durations = csv_data.Duration;
    else
        warning('combined_data_all.csv not found at %s — durations will be missing.', combined_csv);
        csv_ids       = string({});
        csv_durations = [];
    end

    subject_names = string({subject_entries.name});
    [~, match_idx] = ismember(subject_names, csv_ids);

    durations = nan(numSubjects, 1);
    has_match = match_idx > 0;
    durations(has_match) = csv_durations(match_idx(has_match));

    % Sort by duration ascending; subjects without a match go to the end
    [durations_sorted, sort_idx] = sort(durations, 'ascend', 'MissingPlacement', 'last');
    subject_entries = subject_entries(sort_idx);

    % ── Load shared base images ────────────────────────────────────────────
    base  = uint8(imread('base.png'));
    base2 = base(10:531, 33:203, :);
    mask  = imread('mask.png');

    % ── Paginate ──────────────────────────────────────────────────────────
    numPages = ceil(numSubjects / subjects_per_page);

    for page = 1:numPages
        start_idx = (page - 1) * subjects_per_page + 1;
        end_idx   = min(page  * subjects_per_page,  numSubjects);
        page_subjects = subject_entries(start_idx:end_idx);
        n_on_page     = length(page_subjects);

        if save_only
            fig = figure('Units','normalized','Position',[0.05 0.05 0.9 0.85], ...
                         'Name', sprintf('Subjects %d-%d of %d', start_idx, end_idx, numSubjects), ...
                         'Visible', 'off');
        else
            fig = figure('Units','normalized','Position',[0.05 0.05 0.9 0.85], ...
                         'Name', sprintf('Subjects %d-%d of %d', start_idx, end_idx, numSubjects));
        end

        root_tl = tiledlayout(n_on_page, 1, 'TileSpacing','none','Padding','tight');

        for s = 1:n_on_page
            subject     = page_subjects(s);
            subject_dir = fullfile(basepath, subject.name);
            fprintf('Processing subject %s...\n', subject.name);

            subj_tl = tiledlayout(root_tl, 1, 9);
            subj_tl.Layout.Tile = s;

            % ── Subject label (tile 1) ────────────────────────────────────
            ax_label = nexttile(subj_tl, 1);
            axis(ax_label, 'off');
            row = find(csv_ids == string(subject.name), 1);
            if ~isempty(row)
                label_text = sprintf('%s\n%.1f sec', subject.name, csv_durations(row));
            else
                label_text = sprintf('%s\n(no duration)', subject.name);
            end
            text(ax_label, 0.5, 0.5, label_text, ...
                 'HorizontalAlignment','center','VerticalAlignment','middle', ...
                 'FontSize',10,'FontWeight','bold');

            % ── Trial files for this subject ──────────────────────────────
            files     = dir(fullfile(subject_dir, '*.csv'));
            filenames = {files.name};

            % Nostalgia trials (tiles 2–5)
            for n = 1:4
                ax = nexttile(subj_tl, n + 1);
                pattern    = sprintf('-Nost%d.csv', n);
                trial_file = filenames(contains(filenames, pattern));
                if ~isempty(trial_file)
                    data = load_single_sample(fullfile(subject_dir, trial_file{1}));
                    over = reconstruct_painting(data, base);
                    over2 = over(10:531,33:203,:) - over(10:531,696:866,:);
                    plot_sample(ax, base2, over2, mask);
                    title(ax, sprintf('Nost-%d', n), 'FontSize', 8);
                else
                    create_missing_tile(ax, sprintf('Nost-%d', n));
                end
            end

            % Control trials (tiles 6–9)
            for c = 1:4
                ax = nexttile(subj_tl, 5 + c);
                pattern    = sprintf('-Cont%d.csv', c);
                trial_file = filenames(contains(filenames, pattern));
                if ~isempty(trial_file)
                    data = load_single_sample(fullfile(subject_dir, trial_file{1}));
                    over = reconstruct_painting(data, base);
                    over2 = over(10:531,33:203,:) - over(10:531,696:866,:);
                    plot_sample(ax, base2, over2, mask);
                    title(ax, sprintf('Cont-%d', c), 'FontSize', 8);
                else
                    create_missing_tile(ax, sprintf('Cont-%d', c));
                end
            end
        end

        % Colorbar and page title
        h = colorbar;
        h.Layout.Tile = 'east';
        h.Label.String = 'Painting Intensity';

        min_dur = min(durations_sorted(start_idx:end_idx), [], 'omitnan');
        max_dur = max(durations_sorted(start_idx:end_idx), [], 'omitnan');
        sgtitle(sprintf('%s — subjects %d-%d of %d | duration: %.0f–%.0f sec', ...
                        country, start_idx, end_idx, numSubjects, min_dur, max_dur), ...
                'FontSize', 14, 'FontWeight', 'bold');

        % Save
        out_file = fullfile(output_folder, ...
                            sprintf('subjects_page_%d_of_%d.png', page, numPages));
        saveas(fig, out_file, 'png');
        fprintf('Saved: %s\n', out_file);

        if save_only, close(fig); end
    end
end


%% ── Private helpers ──────────────────────────────────────────────────────────

function data = load_single_sample(filepath)
    line  = dlmread(filepath, ',');
    delim = find(line(:,1) == -1);
    if length(delim) < 3
        error('File format error: %s', filepath);
    end
    data.mouse     = line(1:delim(1)-1, :);
    data.paint     = line(delim(1)+1:delim(2)-1, :);
    data.mousedown = line(delim(2)+1:delim(3)-1, :);
    data.mouseup   = line(delim(3)+1:end, :);
end

function over = reconstruct_painting(data, base)
    T    = length(data.paint(:,2));
    over = zeros(size(base,1), size(base,2));
    for t = 1:T
        y = min(max(ceil(data.paint(t,3) + 1), 1), 600);
        x = min(max(ceil(data.paint(t,2) + 1), 1), 900);
        over(y,x) = over(y,x) + 1;
    end
    h    = fspecial('gaussian', [15 15], 5);
    over = imfilter(over, h);
end

function plot_sample(ax, base2, data, mask)
    M = max(abs(data(:)));
    if M == 0, M = 1; end
    NumCol  = 64;
    hotmap  = hot(NumCol);
    coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
    imagesc(ax, base2);
    axis(ax, 'off'); hold(ax, 'on');
    fh = imagesc(ax, data, [-M M]);
    axis(ax, 'off'); axis(ax, 'equal');
    colormap(ax, [coldmap; hotmap]);
    set(fh, 'AlphaData', mask);
end

function create_missing_tile(ax, label)
    axis(ax, 'off');
    text(ax, 0.5, 0.5, sprintf('%s\nMissing', label), ...
         'HorizontalAlignment','center','VerticalAlignment','middle', ...
         'Color','red','FontSize',8);
    rectangle(ax, 'Position',[0 0 1 1], 'EdgeColor','red', 'LineWidth',1);
end