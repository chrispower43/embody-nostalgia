%% Short matlab demo to load and visualize emBODY data - Individual Trials Version
% Adapted from code by Enrico Glerean, Lauri Nummenmaa, and Christopher Henry
% Modified to display individual trials rather than averages

% let's begin
close all
clear

% get a list of subjects
basepath='final&new_subjects'; % folder where subjects are

fixSubjectNaming(basepath);
generate_presentations(basepath);

subjects=dir([basepath '/*']);

% the base image used for painting (in our case only one sided since we
% subtract values)
base=uint8(imread('base.png'));
base2=base(10:531,33:203,:); % single image base
mask=imread('mask.png');

% for each subject, load data
for s=1:length(subjects)
    % skip dot and dotdot folders
    if(strcmp(subjects(s).name(1),'.')) continue; end 

    fprintf('Processing subject %s...\n', subjects(s).name);
    
    %% Data loading
    % let's load the subject's answers into a variable
    data=load_subj([basepath '/' subjects(s).name],2,subjects(s).name);
    NC=length(data); % number of conditions
    
    %% Identify condition types from filenames
    nostalgia_idx = [];
    control_idx = [];
    
    % Get list of CSV files in subject directory
    files = dir([basepath '/' subjects(s).name '/*.csv']);
    filenames = {files.name};
    
    % Find indices for each condition type
    for f = 1:length(filenames)
        if contains(filenames{f}, 'Nost')
            nostalgia_idx = [nostalgia_idx, f];
        elseif contains(filenames{f}, 'Cont')
            control_idx = [control_idx, f];
        end
    end
    
    % Print warning if missing trials
    if length(nostalgia_idx) < 4
        if length(nostalgia_idx) == 0
            fprintf('  DISCARDING Subject %s: %d nostalgia samples, \n', ...
                    subjects(s).name, length(nostalgia_idx));
            continue;
        end;
        fprintf('  Warning: Subject %s has only %d nostalgia samples (expected 4)\n', ...
                subjects(s).name, length(nostalgia_idx));
    end
    if length(control_idx) < 4
        if length(control_idx) == 0
            fprintf('  DISCARDING Subject %s: %d control samples \n', ...
                    subjects(s).name, length(control_idx));
            continue;
        end;
        fprintf('  Warning: Subject %s has only %d control samples (expected 4)\n', ...
                subjects(s).name, length(control_idx));
    end
    
    %% Painting reconstruction
    resmat = [];
    for n=1:NC
        T=length(data(n).paint(:,2)); % number of mouse locations
        over=zeros(size(base,1),size(base,2)); % empty matrix to reconstruct painting
        for t=1:T
            y=ceil(data(n).paint(t,3)+1);
            x=ceil(data(n).paint(t,2)+1);
            if(x<=0) x=1; end
            if(y<=0) y=1; end
            if(x>=900) x=900; end % hardcoded for our experiment, you need to change it if you changed layout
            if(y>=600) y=600; end % hardcoded for our experiment, you need to change it if you changed layout
            over(y,x)=over(y,x)+1;
        end

        % Simulate brush size with a gaussian disk
        h=fspecial('gaussian',[15 15],5);
        over=imfilter(over,h);
        % we subtract left part minus right part of painted area
        % values are hard-coded to our web layout
        over2=over(10:531,33:203,:)-over(10:531,696:866,:);
        resmat(:,:,n)=over2;

    end
    
    %% Extract individual trials
    if ~isempty(nostalgia_idx)
        nostalgia_trials = resmat(:,:,nostalgia_idx);
    else
        nostalgia_trials = [];
        fprintf('  Error: Subject %s has no nostalgia trials!\n', subjects(s).name);
    end
    
    if ~isempty(control_idx)
        control_trials = resmat(:,:,control_idx);
    else
        control_trials = [];
        fprintf('  Error: Subject %s has no control trials!\n', subjects(s).name);
    end
    
    %save(['preprocessed/' subjects(s).name '_preprocessed.mat'], 'nostalgia_trials', 'control_trials');
    
    %% Determine number of trials for each condition
    num_nostalgia = size(nostalgia_trials, 3);
    num_control = size(control_trials, 3);
    max_trials = max(num_nostalgia, num_control);
    
    %% Find maximum value for consistent color scaling
    combined_data = cat(3, nostalgia_trials, control_trials);
    M = max(abs(combined_data(:))); % max range for colorbar
    NumCol = 64;
    hotmap = hot(NumCol);
    coldmap = flipud([hotmap(:,3) hotmap(:,2) hotmap(:,1)]);
    hotcoldmap = [coldmap; hotmap];
    
    %% Create figure with all trials
    figure(s)
    set(gcf,'Color',[1 1 1]);
    set(gcf, 'Position', [100, 100, 800, 400*max_trials]);
    
    % Plot nostalgia trials
    for n = 1:num_nostalgia
        subplot(2, max_trials, (n-1)*2 + 1)
        imagesc(base2);
        axis('off');
        hold on;
        fh = imagesc(nostalgia_trials(:,:,n),[-M,M]);
        axis('off');
        axis equal
        colormap(hotcoldmap);
        set(fh,'AlphaData',mask)
        title(sprintf('Nostalgia Trial %d', n),'FontSize',10)
    end
    
    % Plot control trials
    for c = 1:num_control
        subplot(2, max_trials, (c-1)*2 + 2)
        imagesc(base2);
        axis('off');
        hold on;
        fh = imagesc(control_trials(:,:,c),[-M,M]);
        axis('off');
        axis equal
        colormap(hotcoldmap);
        set(fh,'AlphaData',mask)
        title(sprintf('Control Trial %d', c),'FontSize',10)
    end
    
    % Add colorbar
    colorbar('Position',[0.92 0.2 0.02 0.6])
    
    sgtitle(['Subject ', subjects(s).name, ' - Individual Trials'],'Color','red')
    
    % Optional: save screenshot
    % saveas(gcf,[subjects(s).name '_trials.png'])
end