
function data = load_subj(folder, option, name)
    % Print which folder is being loaded
    disp(['Loading folder: ' folder]);

    % Read presentation.txt as a list of filenames (one per line)
    fid = fopen([folder '/presentation.txt'], 'r');
    filelist = textscan(fid, '%s', 'Delimiter', '\n');
    fclose(fid);
    
    files = filelist{1};
    N = length(files);

    if option == 0
        disp('Option 0 not implemented')
        % disp('Option 0: Loading as raw strings (textscan with semicolon delimiter)');
        % for n = 1:N
        %     file = [folder '/' files{n}];
        %     fid = fopen(file);
        %     if fid == -1
        %         error(['Could not open file: ' file]);
        %     end
        %     line = textscan(fid, '%s', 'CollectOutput', 1, 'Delimiter', ';');
        %     fclose(fid);
        %     data(:,n) = line{1};
        % end
        % data = data';
    elseif option == 1
        disp('Option 1 not implemented');
    elseif option == 2
        disp('Option 2+: Loading structured mouse/paint/down/up data');
        for n = 1:N
            file = [folder '/' name '-' files{n}];
            line = dlmread(file, ',');
            delim = find(line(:,1) == -1);
            if length(delim) < 3
                error(['File format error: ' file]);
            end
            data(n).mouse    = line(1:delim(1)-1, :);
            data(n).paint    = line(delim(1)+1 : delim(2)-1, :);
            data(n).mousedown = line(delim(2)+1 : delim(3)-1, :);
            data(n).mouseup   = line(delim(3)+1 : end, :);
        end
    end
    if(option ==3)
        for n=0:N-1;
            file=[folder '/' num2str(n) '.csv'];

            line=dlmread(file,',');
            delim=find(-1==line(:,1));
            data(n+1).mouse=line(1:delim(1)-1,:);
            data(n+1).paint=line((delim(1)+1):(delim(2)-1),:);
            data(n+1).mousedown=line((delim(2)+1):(delim(3)-1),:);
            data(n+1).mouseup=line((delim(3)+1):end,:);
        end
    end
end
