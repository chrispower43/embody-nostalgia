function fixSubjectNaming(basepath)
% FIXSUBJECTNAMING Renames subject folders and files by removing 'R_' prefix
%   fixSubjectNaming(basepath) processes all subject folders in the specified
%   basepath that start with 'R_', removing this prefix from both folder names
%   and all associated CSV files.

    % Get all subject folders starting with 'R_'
    subjects = dir(fullfile(basepath, 'R_*'));
    subjects = subjects([subjects.isdir]); % Keep only directories
    
    for i = 1:length(subjects)
        oldFolderName = subjects(i).name;
        newFolderName = oldFolderName(3:end); % Remove 'R_'
        
        oldFolderPath = fullfile(basepath, oldFolderName);
        newFolderPath = fullfile(basepath, newFolderName);
        
        % Check if new folder name already exists to avoid conflicts
        if exist(newFolderPath, 'dir')
            warning('Folder %s already exists. Skipping rename of %s.', ...
                   newFolderName, oldFolderName);
            continue;
        end
        
        % Rename the folder
        movefile(oldFolderPath, newFolderPath);
        fprintf('Renamed folder: %s -> %s\n', oldFolderName, newFolderName);
        
        % Process all CSV files in the folder
        csvFiles = dir(fullfile(newFolderPath, 'R_*.csv'));
        for j = 1:length(csvFiles)
            oldFileName = csvFiles(j).name;
            newFileName = oldFileName(3:end); % Remove 'R_'
            
            oldFilePath = fullfile(newFolderPath, oldFileName);
            newFilePath = fullfile(newFolderPath, newFileName);
            
            % Rename the file
            movefile(oldFilePath, newFilePath);
            fprintf('  Renamed file: %s -> %s\n', oldFileName, newFileName);
        end
        
        % Delete the directory if it's empty after processing
        remainingFiles = dir(newFolderPath);
        if length(remainingFiles) == 2  % Only '.' and '..' remain
            rmdir(newFolderPath);
            fprintf('Deleted empty directory: %s\n', newFolderPath);
        end
    end
    
    fprintf('Done processing %d subjects.\n', length(subjects));
end