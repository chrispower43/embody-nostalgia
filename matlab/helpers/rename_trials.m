function renameTrials(subjectsPath)
% RENAME_TRIALS Renames control and nostalgia trial files
%   Control: Cont10->Cont1, Cont20->Cont2, Cont30->Cont3, Cont40->Cont4
%   Nostalgia: Nost01->Nost1, Nost02->Nost2, Nost03->Nost3, Nost04->Nost4

    % Get all subdirectories (subject folders)
    subjectDirs = dir(subjectsPath);
    subjectDirs = subjectDirs([subjectDirs.isdir]); % Keep only directories
    subjectDirs = subjectDirs(~ismember({subjectDirs.name}, {'.', '..'})); % Remove . and ..
    
    % Define the mapping from old names to new names
    renameMap = {'Cont10', 'Cont1';
                 'Cont20', 'Cont2';
                 'Cont30', 'Cont3';
                 'Cont40', 'Cont4';
                 'Nost01', 'Nost1';
                 'Nost02', 'Nost2';
                 'Nost03', 'Nost3';
                 'Nost04', 'Nost4'};
    
    % Process each subject directory
    for d = 1:length(subjectDirs)
        currentSubjectPath = fullfile(subjectsPath, subjectDirs(d).name);
        
        % Get all CSV files in this subject's directory (both Cont and Nost)
        files = dir(fullfile(currentSubjectPath, '*.csv'));
        
        % Process each file
        for i = 1:length(files)
            oldFilename = files(i).name;
            newFilename = oldFilename;
            
            % Check and replace each pattern
            for j = 1:size(renameMap, 1)
                oldPattern = renameMap{j, 1};
                newPattern = renameMap{j, 2};
                
                if contains(oldFilename, oldPattern)
                    newFilename = strrep(oldFilename, oldPattern, newPattern);
                    break; % Only one replacement per file
                end
            end
            
            % Rename the file if the name changed
            if ~strcmp(oldFilename, newFilename)
                oldPath = fullfile(currentSubjectPath, oldFilename);
                newPath = fullfile(currentSubjectPath, newFilename);
                
                try
                    movefile(oldPath, newPath);
                    fprintf('Renamed: %s -> %s\n', oldFilename, newFilename);
                catch ME
                    fprintf('Error renaming %s: %s\n', oldFilename, ME.message);
                end
            end
        end
    end
end