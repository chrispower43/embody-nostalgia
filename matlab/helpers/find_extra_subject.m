%% find_extra_subject()


function find_extra_subject(base_dir)
    % Base directory path
    if nargin <1 
        base_dir = 'C:\Users\henry\MATLAB\Projects\untitled\matlab\final&new_subjects';
    end

    % Get list of country directories (excluding 'all' and system directories)
    country_dirs = dir(base_dir);
    country_dirs = country_dirs([country_dirs.isdir]);
    country_dirs = country_dirs(~ismember({country_dirs.name}, {'.', '..', 'all'}));
    
    % Get all subjects from country directories with country information
    country_subjects = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    subject_country_map = containers.Map('KeyType', 'char', 'ValueType', 'char'); % New: map subject to country
    country_subjects_list = {};
    
    fprintf('Scanning country directories for subjects...\n');
    for i = 1:length(country_dirs)
        country_name = country_dirs(i).name;
        country_path = fullfile(base_dir, country_name, 'subjects');
        
        if isfolder(country_path)
            % Get all subject directories in this country
            subject_dirs = dir(country_path);
            subject_dirs = subject_dirs([subject_dirs.isdir]);
            subject_dirs = subject_dirs(~ismember({subject_dirs.name}, {'.', '..'}));
            
            fprintf('Country %s: %d subjects\n', country_name, length(subject_dirs));
            
            % Add subjects to our map and list
            for j = 1:length(subject_dirs)
                subject_name = subject_dirs(j).name;
                country_subjects(subject_name) = true;
                subject_country_map(subject_name) = country_name; % Store country info
                country_subjects_list{end+1} = subject_name;
            end
        end
    end
    
    fprintf('\nTotal unique subjects in country directories: %d\n', country_subjects.Count);
    
    % Get all subjects from 'all' directory
    all_dir_path = fullfile(base_dir, 'all/subjects/');
    all_subject_dirs = dir(all_dir_path);
    all_subject_dirs = all_subject_dirs([all_subject_dirs.isdir]);
    all_subject_dirs = all_subject_dirs(~ismember({all_subject_dirs.name}, {'.', '..'}));
    
    all_subjects_list = {all_subject_dirs.name};
    fprintf('Subjects in ''all'' directory: %d\n', length(all_subjects_list));
    
    % Find subjects in 'all' that are not in any country directory
    all_not_in_country = {};
    for i = 1:length(all_subjects_list)
        subject_name = all_subjects_list{i};
        if ~isKey(country_subjects, subject_name)
            all_not_in_country{end+1} = subject_name;
        end
    end
    
    % Find subjects in country directories that are not in 'all'
    country_not_in_all = {};
    country_info_not_in_all = {}; % New: store country info for each orphaned subject
    for i = 1:length(country_subjects_list)
        subject_name = country_subjects_list{i};
        if ~ismember(subject_name, all_subjects_list)
            country_not_in_all{end+1} = subject_name;
            country_info_not_in_all{end+1} = subject_country_map(subject_name); % Get country
        end
    end
    
    % Display results
    fprintf('\n=== BIJECTIVE CHECK RESULTS ===\n');
    
    % Report subjects in 'all' but not in countries
    if isempty(all_not_in_country)
        fprintf(' All subjects in ''all'' directory exist in country directories.\n');
    else
        fprintf('Found %d subject(s) in ''all'' directory but not in any country directory:\n', length(all_not_in_country));
        for i = 1:length(all_not_in_country)
            fprintf('  - %s\n', all_not_in_country{i});
        end
    end
    
    % Report subjects in countries but not in 'all' (with country information)
    if isempty(country_not_in_all)
        fprintf('All subjects in country directories exist in ''all'' directory.\n');
    else
        fprintf('Found %d subject(s) in country directories but not in ''all'' directory:\n', length(country_not_in_all));
        for i = 1:length(country_not_in_all)
            fprintf('  - %s (Country: %s)\n', country_not_in_all{i}, country_info_not_in_all{i});
        end
    end
    
    % Summary statistics
    fprintf('\n=== SUMMARY ===\n');
    fprintf('Total subjects in ''all'' directory: %d\n', length(all_subjects_list));
    fprintf('Total unique subjects in country directories: %d\n', country_subjects.Count);
    fprintf('Subjects only in ''all'': %d\n', length(all_not_in_country));
    fprintf('Subjects only in countries: %d\n', length(country_not_in_all));
    
    % Calculate intersection (subjects in both)
    common_subjects = intersect(all_subjects_list, country_subjects_list);
    fprintf('Common subjects (in both ''all'' and countries): %d\n', length(common_subjects));
    
    if isempty(all_not_in_country) && isempty(country_not_in_all)
        fprintf('\nPerfect bijective relationship! All subjects match between ''all'' and country directories.\n');
    else
        fprintf('\n Directory structure is not bijective. There are mismatched subjects.\n');
    end
end