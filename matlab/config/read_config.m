function cfg = read_config(config_path)
%READ_CONFIG  Parse config.toml and return a convenient struct.
%
%   cfg = read_config()               reads config.toml in the current folder
%   cfg = read_config('path/to/config.toml')
%
%   Returned struct fields
%   ──────────────────────
%   cfg.subjects_dir      char    active cohort root folder
%   cfg.qualtrics_data    char    qualtrics CSV folder
%   cfg.prolific_data     char    prolific CSV folder
%   cfg.combined_csv      char    path to combined_data_all.csv
%   cfg.regression_csv    char    path to regression_all.csv
%   cfg.countries         cell    per-country list  {'BR','IN','US','SP','JP'}
%   cfg.countries_all     cell    includes 'all' aggregate dir
%   cfg.target_paired     double  pruning target (paired pipeline)
%   cfg.target_all        double  pruning target (all pipeline)
%   cfg.pic_prefix        char    prefix string for all saved figures
%   cfg.pic_pq0           char    pictures/PQ0  (with prefix already embedded)
%   cfg.pic_pq1and3       char    pictures/PQ1&3
%   cfg.pic_regression    char    pictures/regression
%
%   Example usage in a MATLAB script
%   ─────────────────────────────────
%   cfg = read_config();
%   files = dir(fullfile(cfg.subjects_dir, 'all', 'preprocessed', '*.mat'));
%   saveas(fig, fullfile(cfg.pic_pq0, [cfg.pic_prefix 'Tmap_US.png']));

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'helpers'));

    if nargin < 1
        project_root = fileparts(mfilename('fullpath'));
        config_path = fullfile(project_root, 'config.toml');
    end
    if ~isfile(config_path)
        error('read_config:notFound', ...
              'Config file not found: %s\nExpected it next to your MATLAB scripts.', ...
              config_path);
    end

    raw = fileread(config_path);
    lines = splitlines(string(raw));

    % ── Minimal TOML parser ──────────────────────────────────────────────────
    % Supports: [section], key = "string", key = integer, key = ["a","b","c"]
    % Does not support: nested tables, inline tables, multi-line strings, dates.
    section = '';
    data    = struct();

    for i = 1:numel(lines)
        line = strtrim(lines(i));

        % Skip blank lines and comments
        if line == "" || startsWith(line, '#'), continue; end

        % Remove inline comments
        comment_pos = strfind(char(line), ' #');
        if ~isempty(comment_pos)
            line = string(strtrim(line.extractBefore(comment_pos(1))));
        end

        % Section header  [section] or [section.subsection]
        if startsWith(line, '[') && endsWith(line, ']')
            % Convert  [pictures.subfolders]  ->  field path  pictures_subfolders
            inner   = char(line.extractBetween('[', ']'));
            section = strrep(inner, '.', '_');
            if ~isfield(data, section)
                data.(section) = struct();
            end
            continue;
        end

        % Key = value
        eq = strfind(char(line), '=');
        if isempty(eq), continue; end

        key = strtrim(line.extractBefore(eq(1)));
        val = strtrim(line.extractAfter(eq(1)));
        key = char(key);

        % Parse value type
        if startsWith(val, '"') && endsWith(val, '"')
            % Quoted string
            parsed = char(val.extractBetween('"', '"'));

        elseif startsWith(val, '[') && endsWith(val, ']')
            % Array of quoted strings  ["a", "b", "c"]
            inner_arr = char(val.extractBetween('[', ']'));
            parts     = strsplit(inner_arr, ',');
            parsed    = cell(1, numel(parts));
            for k = 1:numel(parts)
                p = strtrim(string(parts{k}));
                if startsWith(p, '"') && endsWith(p, '"')
                    parsed{k} = char(p.extractBetween('"', '"'));
                else
                    parsed{k} = char(p);
                end
            end

        else
            % Numeric (integer or float)
            num = str2double(val);
            if isnan(num)
                parsed = char(val);   % fallback: keep as string
            else
                parsed = num;
            end
        end

        % Store into the correct section or root
        if isempty(section)
            data.(key) = parsed;
        else
            data.(section).(key) = parsed;
        end
    end

    % ── Build the convenience struct ─────────────────────────────────────────
    cfg = struct();

    % Paths
    cfg.subjects_dir   = field(data, 'paths', 'subjects_dir',   'final&new_subjects');
    cfg.qualtrics_data = field(data, 'paths', 'qualtrics_data', 'qualtrics_data');
    cfg.prolific_data  = field(data, 'paths', 'prolific_data',  'prolific_data');
    cfg.combined_csv   = field(data, 'paths', 'combined_csv',   'combined_data_all.csv');

    % Countries
    cfg.countries     = field(data, 'countries', 'list',         {'BR','IN','US','SP','JP'});
    cfg.countries_all = field(data, 'countries', 'with_aggregate', {'BR','IN','US','SP','JP','all'});

    % Pruning
    cfg.target_paired = field(data, 'pruning', 'target_paired', 60);
    cfg.target_all    = field(data, 'pruning', 'target_all',    70);

    % Picture prefix: auto-derive from subjects_dir unless override is set
    override = field(data, 'pictures', 'prefix_override', '');
    if isempty(override)
        cfg.pic_prefix = derive_prefix(cfg.subjects_dir);
    else
        cfg.pic_prefix = override;
    end

    % Picture subfolders — include prefix in the folder name so figures from
    % different cohorts land in separate, clearly-labelled subdirectories.
    base_pq0        = field(data, 'pictures_subfolders', 'pq0',        'PQ0');
    base_pq1and3    = field(data, 'pictures_subfolders', 'pq1and3',    'PQ1&3');
    base_regression = field(data, 'pictures_subfolders', 'regression', 'regression');

    if ~isempty(cfg.pic_prefix)
        % e.g.  pictures/Copy_PQ0
        cfg.pic_pq0        = fullfile('pictures', [cfg.pic_prefix base_pq0]);
        cfg.pic_pq1and3    = fullfile('pictures', [cfg.pic_prefix base_pq1and3]);
        cfg.pic_regression = fullfile('pictures', [cfg.pic_prefix base_regression]);
        cfg.pca_regression = fullfile('pictures', [cfg.pic_prefix 'pca_' base_regression]);
        cfg.multi_regression = fullfile('pictures', [cfg.pic_prefix 'multi_' base_regression]);
    else
        cfg.pic_pq0        = fullfile('pictures', base_pq0);
        cfg.pic_pq1and3    = fullfile('pictures', base_pq1and3);
        cfg.pic_regression = fullfile('pictures', base_regression);
        cfg.pca_regression = fullfile('pictures', ['pca_' base_regression]);
        cfg.multi_regression = fullfile('pictures', ['multi_' base_regression]);
        
    end
end


% ── Helpers ──────────────────────────────────────────────────────────────────

function v = field(data, section, key, default)
%FIELD  Safe accessor with fallback default.
    if isfield(data, section) && isfield(data.(section), key)
        v = data.(section).(key);
    else
        v = default;
    end
end

function prefix = derive_prefix(subjects_dir)
%DERIVE_PREFIX  Turn a subjects_dir name into a short file prefix.
%
%   "final&new_subjects"          ->  ""           (canonical name, no prefix)
%   "final&new_subjects - Copy"   ->  "Copy_"
%   "pilot_data"                  ->  "pilot_data_"
    canonical = 'final&new_subjects';
    if strcmp(subjects_dir, canonical)
        prefix = '';
        return;
    end

    % Strip leading canonical portion if present  ("final&new_subjects - Copy"
    % -> " - Copy"  -> "Copy")
    remainder = strtrim(strrep(subjects_dir, canonical, ''));
    % Strip leading dash/hyphen separators
    remainder = regexprep(remainder, '^[-–—\s]+', '');
    % Replace spaces with underscores and ensure trailing underscore
    remainder = strrep(remainder, ' ', '_');
    if ~isempty(remainder) && remainder(end) ~= '_'
        remainder = [remainder '_'];
    end
    prefix = remainder;
end
