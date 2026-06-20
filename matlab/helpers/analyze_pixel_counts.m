% analyze_pixel_counts.m
% Usage examples:
%   analyze_pixel_counts();                % uses default paths and settings
%   analyze_pixel_counts('subjects/all',5,20); % basepath, top N, number of bins
%
% What it does:
%  - looks in [basepath '/preprocessed/'] for files matching '*_preprocessed.mat'
%  - for each subject loads nostalgia_avg and control_avg if present (or any
%    non-empty variable in the file), computes number of non-zero pixels
%    (optionally inside mask.png if present)
%  - plots a bar graph of how many participants fall into each pixel-count bucket
%  - prints and displays the top N participants with the fewest pixels drawn

function analyze_pixel_counts(basepath, topN, numBins)
close all
clear 
if nargin < 1 || isempty(basepath)
    basepath = 'subjects/SP'; % default, change to your path as needed
end
if nargin < 2 || isempty(topN)
    topN = 10;
end
if nargin < 3 || isempty(numBins)
    numBins = 20;
end

preproc_dir = fullfile(basepath, 'preprocessed');
if ~isfolder(preproc_dir)
    error('Preprocessed directory not found: %s', preproc_dir);
end

% Try to load mask if it exists in current folder
maskFile = 'mask.png';
useMask = false;
if isfile(maskFile)
    try
        maskImg = imread(maskFile);
        % create logical mask: nonzero/white area
        if ndims(maskImg) == 3
            mask = any(maskImg > 128, 3);
        else
            mask = maskImg > 128;
        end
        % crop/resize mask if needed: assume preprocessed maps are same dims as mask
        useMask = true;
        fprintf('Using mask from %s\n', maskFile);
    catch
        useMask = false;
        fprintf('Failed to load mask.png, proceeding without mask.\n');
    end
else
    fprintf('No mask.png found; counting non-zero across full maps.\n');
end

files = dir(fullfile(preproc_dir, '*_preprocessed.mat'));
if isempty(files)
    error('No preprocessed .mat files found in %s', preproc_dir);
end

subjectNames = cell(length(files),1);
pixelCounts   = zeros(length(files),1);
mapsForDisplay = cell(length(files),1); % store combined map (nost+cont) for display

for k = 1:length(files)
    fname = fullfile(preproc_dir, files(k).name);
    try
        S = load(fname);
    catch ME
        warning('Failed to load %s: %s', files(k).name, ME.message);
        continue;
    end

    subjectNames{k} = files(k).name;
    % Prefer nostalgia_avg and control_avg if present
    map = [];
    if isfield(S, 'nostalgia_avg') && ~isempty(S.nostalgia_avg)
        map = S.nostalgia_avg;
    end
    if isfield(S, 'control_avg') && ~isempty(S.control_avg)
        if isempty(map)
            map = S.control_avg;
        else
            % combine the two (absolute sum) for a union view
            % use absolute values because maps may be signed
            map = abs(map) + abs(S.control_avg);
        end
    end

    % if neither exist, try to find any 2D variable in file and use its mean across pages
    if isempty(map)
        fnames = fieldnames(S);
        found = false;
        for f = 1:numel(fnames)
            v = S.(fnames{f});
            if isnumeric(v) && ndims(v) >= 2
                % if 3D (n_maps), collapse by mean
                if ndims(v) == 3
                    map = mean(v,3);
                else
                    map = v;
                end
                found = true;
                break;
            end
        end
        if ~found
            warning('No usable map found in %s; setting count to 0.', files(k).name);
            pixelCounts(k) = 0;
            mapsForDisplay{k} = [];
            continue;
        end
    end

    % ensure map is 2D numeric
    if ~isnumeric(map) || ndims(map) ~= 2
        warning('Map for %s is not 2D numeric; skipping.', files(k).name);
        pixelCounts(k) = 0;
        mapsForDisplay{k} = [];
        continue;
    end

    % If mask exists and is same size, apply it; else if different size, try crop/resize
    if useMask
        if all(size(mask) == size(map))
            mapMasked = map .* double(mask);
        else
            % try to center-crop or resample mask to map size
            try
                mask_resized = imresize(double(mask), size(map), 'nearest');
                mapMasked = map .* mask_resized;
            catch
                % fall back to no mask
                mapMasked = map;
            end
        end
    else
        mapMasked = map;
    end

    % count non-zero pixels (anything not equal to zero)
    pixelCounts(k) = nnz(mapMasked ~= 0);
    mapsForDisplay{k} = mapMasked;
end

% Trim empty entries (if any file failed to load)
validIdx = ~cellfun(@isempty, subjectNames);
subjectNames = subjectNames(validIdx);
pixelCounts = pixelCounts(validIdx);
mapsForDisplay = mapsForDisplay(validIdx);

% Sort subjects by pixel count (ascending)
[sortedCounts, sortIdx] = sort(pixelCounts);
sortedNames = subjectNames(sortIdx);

% --- Create histogram / bar plot with buckets ---
maxCount = max(sortedCounts);
if maxCount == 0
    binEdges = [0 1];
else
    binEdges = linspace(0, maxCount, numBins+1);
end

[countsPerBin, edges] = histcounts(sortedCounts, binEdges);

figure('Name','Pixel counts per participant','Color','w','Units','normalized','Position',[0.2 0.2 0.55 0.45]);
barCenters = edges(1:end-1) + diff(edges)/2;
bar(barCenters, countsPerBin, 'BarWidth', 1);
xlabel('Number of non-zero pixels (bucket center)');
ylabel('Number of participants');
title(sprintf('Distribution of non-zero pixels across %d participants', numel(sortedCounts)));
grid on;

% nice x ticks
xticks(barCenters(1: max(1,floor(numel(barCenters)/10)) : end));
xtickangle(45);

% also show basic stats
medianCount = median(sortedCounts);
meanCount = mean(sortedCounts);
text(0.02,0.95,sprintf('Median = %d\nMean = %.1f', round(medianCount), meanCount), ...
    'Units','normalized','HorizontalAlignment','left','BackgroundColor','w');

% --- Display top N participants with fewest pixels drawn ---
topN = min(topN, numel(sortedCounts));
fprintf('\nTop %d participants with the FEWEST non-zero pixels:\n', topN);
T = table((1:topN)', sortedNames(1:topN), sortedCounts(1:topN), ...
    'VariableNames', {'Rank','SubjectFile','NonZeroPixelCount'});
disp(T);

% Visualize their maps (combined) in a figure
if topN > 0
    figure('Name',sprintf('Top %d fewest-drawn participants', topN),'Color','w','Units','normalized','Position',[0.1 0.1 0.8 0.7]);
    nCols = min(5, topN);
    nRows = ceil(topN / nCols);
    for ii = 1:topN
        idx = sortIdx(ii);
        mapImg = mapsForDisplay{idx};
        subplot(nRows, nCols, ii);
        if isempty(mapImg)
            imagesc(zeros(10,10)); axis off; title(sprintf('%s\n(%d px)', sortedNames{ii}, sortedCounts(ii)),'Interpreter','none');
            continue;
        end
        % display absolute map for visibility
        imagesc(abs(mapImg));
        axis off; axis image;
        title(sprintf('%s\n(%d px)', sortedNames{ii}, sortedCounts(ii)),'Interpreter','none','FontSize',9);
        colormap(gca, hot); % no color overriding preference
    end
    subtitle(sprintf('Top %d participants with fewest non-zero pixels', topN));
end

end % function
