README:

A brief explanation of the code here:

embody_nost_preprocessing:
- Generates .preprocessed folder in country directory containing .mat files
- each file contains masked data, and only preprocesses paired data (AKA only saves cont1 if nost1 exists). 

embody_nost_all_preprocessing:
- Same thing as before, but preprocesses every control, regardless of corresponding nostalgia trial. 

embody_nost_PQO:
- Runs a t-test against zero, only plots threshold of p=0.05

embody_nost_PQ1and3:
- Paired t-tests, only plots threshold p=0.05.

KFoldCV_LDA.m:
- Performs a k-fold cross validation LDA. (5-fold to match country count)

LDA_LOCO.m: 
-Performs a leave one country out LDA

LOO_LDA.m:
- Performs a leave one participant out LDA. Takes a while to run. 