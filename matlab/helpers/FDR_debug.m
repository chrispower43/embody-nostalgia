function [pID,pN] = FDR_debug(p,q)
% FORMAT [pID,pN] = FDR_debug(p,q)
%
% This version of the classic FDR.m prints key diagnostic information.
%
% p   - vector of p-values
% q   - False Discovery Rate level
%
% pID - p-value threshold assuming independence or positive dependence
% pN  - Nonparametric p-value threshold (conservative)

    % --- Preprocessing ---
    fprintf('--- Running FDR Debug ---\n');
    fprintf('Input q (target FDR): %.4f\n', q);
    fprintf('Original number of p-values: %d\n', numel(p));

    % Remove NaNs and non-finite
    p = p(isfinite(p));
    fprintf('Valid finite p-values: %d\n', numel(p));

    % Sort p-values ascending
    p = sort(p(:));
    V = length(p);
    I = (1:V)';

    % Correction constants
    cVID = 1;
    cVN = sum(1./(1:V));

    % --- Compute thresholds ---
    idxID = find(p <= I/V * q / cVID);
    idxN  = find(p <= I/V * q / cVN);

    if isempty(idxID)
        pID = [];
    else
        pID = p(max(idxID));
    end

    if isempty(idxN)
        pN = [];
    else
        pN = p(max(idxN));
    end

    % --- Print debug info ---
    fprintf('Smallest p: %.6f, Largest p: %.6f\n', p(1), p(end));
    fprintf('cVID = %.6f, cVN = %.6f\n', cVID, cVN);

    if isempty(idxID)
        fprintf('No valid pID found (no p <= (i/V)*q/cVID)\n');
    else
        fprintf('Max index for pID: %d (of %d)\n', max(idxID), V);
        fprintf('FDR independence threshold pID = %.6f\n', pID);
    end

    if isempty(idxN)
        fprintf('No valid pN found (no p <= (i/V)*q/cVN)\n');
    else
        fprintf('Max index for pN: %d (of %d)\n', max(idxN), V);
        fprintf('FDR nonparametric threshold pN = %.6f\n', pN);
    end

    fprintf('-----------------------------------------\n\n');

    %% Diagnostic FDR plot
% Assumes you already have:
%   p  - vector of p-values (in-mask, flattened)
%   q  - desired FDR level (e.g., 0.05)

% Remove NaNs and sort
p_sorted = sort(p(isfinite(p)));
V = length(p_sorted);
I = (1:V)';

% BH threshold curve
cVID = 1;                  % independence / positive correlation
BH_thresh = I/V * q / cVID;

% Find largest rank passing BH
idx_pass = find(p_sorted <= BH_thresh);
if isempty(idx_pass)
    last_idx = NaN;
    fprintf('No p-values pass FDR at q = %.3f\n', q);
else
    last_idx = max(idx_pass);
    fprintf('Largest rank passing BH: %d / %d, pID = %.6f\n', ...
        last_idx, V, p_sorted(last_idx));
end

% Plot
figure(1331);
plot(I, p_sorted, '.', 'MarkerSize', 8); hold on;
plot(I, BH_thresh, 'r-', 'LineWidth', 2); % BH threshold line
if ~isnan(last_idx)
    plot(last_idx, p_sorted(last_idx), 'go', 'MarkerSize', 10, 'LineWidth', 2);
end
xlabel('Rank of p-value (i)');
ylabel('p-value');
title(sprintf('Benjamini-Hochberg FDR (q = %.2f)', q));
legend('Sorted p-values','BH threshold','Largest passing p-value','Location','northwest');
grid on;
set(gca,'YScale','log'); % optional: log scale for clarity

end
