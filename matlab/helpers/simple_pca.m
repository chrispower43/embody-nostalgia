function [data_reduced, pca_coeff] = simple_pca(data, num_components)
% SIMPLE_PCA Barebones PCA for LDA preprocessing
%
% Inputs:
%   data - Matrix of size [num_voxels x num_trials] 
%   num_components - Number of PCA components to keep
%
% Outputs:
%   data_reduced - Reduced data [num_trials x num_components] (ready for LDA)
%   pca_coeff - PCA coefficients for potential reconstruction

% Transpose and perform PCA
data_for_pca = data';
[coeff, score, ~, ~, explained] = pca(data_for_pca, 'NumComponents', num_components);

% Return only what's needed for LDA
data_reduced = score;
pca_coeff = coeff;

% Optional: show basic info
fprintf('PCA: %d voxels -> %d components (%.1f%% variance)\n', ...
    size(data, 1), num_components, sum(explained(1:num_components)));
end