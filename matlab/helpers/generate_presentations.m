function generate_presentations(base_dir)
    if nargin < 1
        error('Usage: generate_presentations(base_dir)');
    end

    if ~isfolder(base_dir)
        error('Directory "%s" does not exist.', base_dir);
    end

    subject_dirs = dir(base_dir);
    
    for i = 1:length(subject_dirs)
        entry = subject_dirs(i);
        
        % Skip non-directories and "." / ".."
        if ~entry.isdir || strcmp(entry.name, '.') || strcmp(entry.name, '..')
            continue;
        end

        subject_path = fullfile(base_dir, entry.name);
        files = dir(subject_path);

        % Prepare path for output
        presentation_path = fullfile(subject_path, 'presentation.txt');
        out_fid = fopen(presentation_path, 'w');
        if out_fid == -1
            warning('Failed to create %s\n', presentation_path);
            continue;
        end

        file_found = false;

        for j = 1:length(files)
            file = files(j);

            if ~file.isdir && is_valid_csv(file.name)
                basename = strip_prefix(file.name);
                fprintf(out_fid, '%s\n', basename);
                file_found = true;
            end
        end

        fclose(out_fid);

        % Delete file if nothing was written
        if ~file_found
            delete(presentation_path);
        end
    end
end

function valid = is_valid_csv(filename)
    % Check for -Chosen or -Nost and .csv extension
    valid = (contains(filename, '-Cont') || contains(filename, '-Nost')) ...
            && endsWith(filename, '.csv');
end

function stripped = strip_prefix(filename)
    % Return string after first dash
    idx = strfind(filename, '-');
    if ~isempty(idx) && idx(1) < length(filename)
        stripped = filename(idx(1)+1:end);
    else
        stripped = filename;
    end
end
