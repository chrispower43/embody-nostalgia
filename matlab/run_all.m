%% Runs all the relevant files

preprocessing

%if it's your first time running these, you may throw an error. Refer to
%README on how to fix
pyrunfile("python_scripts/analyse_ratings.py")
pyrunfile("python_scripts/generate_demographics.py")

zero_ttest
nostalgia_over_control_ttest
control_over_nostalgia_ttest

regression
multiple_regression
exploratory

KFoldCV_LDA
LOCO_LDA
LOO_LDA
