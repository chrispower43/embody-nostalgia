# README

## 1) Setup
This code uses a combination of matlab and python code. Unfortunately, some older versions of MATLAB are incompatible with the newest version of python. 
Therefore, we use a .venv

This script was written using MATLABR2024b, therefore for this to work, you will need a supported version of python installed and on your PATH. 

(For more information on the version of python your version of MATLAB supports, visit https://www.mathworks.com/support/requirements/python-compatibility.html)
(note: these scripts was originally written with Python 3.11. If you follow these steps and it still doesn't work, perhaps try Python3.11 specifically)

Here is the link to download specific version of python for windows (scroll down for specific releases): https://www.python.org/downloads/

The first time you open this script, you must run setup_python_env.m. 
You can do this in the Matlab terminal by cd to your project root, then running setup_python_env.m
Alternatively, you can open the script, switch to the editor tab at the top of the screen and click the green arrow that says "Run"

 This will:
   - create a project-local `.venv` at the project root (via
     `setup/setup_env.sh` on macOS/Linux or `setup/setup_env.bat` on
     Windows) if one doesn't already exist,
   - install the pinned versions in `setup/requirements.txt`,
   - point MATLAB's `pyenv` at that `.venv`'s Python interpreter,
   - verify `numpy`, `pandas`, and `tomli` all import.

Once you see `=== Environment ready. You can now run preprocessing.m ===`,
   run:
```
   preprocessing
```

## 2) Code pipeline and overview
preprocessing.m:
- Should be run at the beginning of every analysis pipeline. 
- Masks out pixel data and applies gaussian filter.
- Creates subfolders of relevant cohorts and subject lists (see structural information)
- Generates .preprocessed folder in country directory containing .mat files
- You will be prompted to either conduct a full run or skip the pixel processing. If it is your first time running preprocessing.m, type 1 and enter. 
- You will then be prompted to conduct pruning. The default behavior is to truncate to whichever country has the least number of participants according to recency 
- (i.e. if SP/prprocessed has 60 participants and US has 71, the default behavior will exclude the 11 participants who most recently completed the survey. Notably, this does not remove them from the the subjects/ folder, so you can include them in future analysis if you run the full pixel processing again)
- This will occur for both the preprocessed and unfiltered cohorts
- Also creates combined_data_all.csv. This is the omnibus CSV which contains information about each subject combined from their Qualtrics responses and Prolific profile data. 

### After preprocessing.m is run, you can run any of the other actual analysis scripts to your hearts content. 

### Python Scripts
You can run any of the python scripts by calling pyrunfile from the project root, i.e. (pyrunfile("python_scripts/analyse_ratings.py"))
The first time you run this script, you'll probably get the following error:
>> pyrunfile("python_scripts/analyse_ratings.py")
Error using <string>><module> (line 51)
Python Error: RuntimeError: EMBODY_PROJECT_ROOT is not set. This script cannot infer its own location when
run via pyrunfile(), so the caller must set this environment variable explicitly before invoking
analyse_ratings.py.
From MATLAB, set it via:
  py.os.environ().update(py.dict(pyargs('EMBODY_PROJECT_ROOT', project_root)))

To fix this simply cd to the project root and run pwd to print the working directory. Then run the command as it says, i.e. 
>> py.os.environ().update(py.dict(pyargs('EMBODY_PROJECT_ROOT', 'C:\Users\henry\MATLAB\Projects\nostlgiav1\embody-nostalgia\matlab')))

Then just run pyrunfile() again. 
>> pyrunfile("python_scripts/analyse_ratings.py")


build_combined_data.py and generate_removal_lists.py are called by preprocessing.m; you likely won't need to call them yourself. 
analyse_ratings.py generates statistics about the nostalgia and control songs
generate_demographics.py generates demographics data for the preprocessed and unfiltered cohorts

--------------------
zero_ttest.m:
- Runs a t-test against zero, only plots threshold of p=0.05

paired_ttest.m:
- Paired t-tests, only plots threshold p=0.05.

KFoldCV_LDA.m:
- Performs a k-fold cross validation LDA. (5-fold to match country count)

LDA_LOCO.m: 
- Performs a leave one country out LDA. i.e. trains on the other countries, tests on held out country. 

LOO_LDA.m:
- Performs a leave one participant out LDA. Takes a while to run, especially if you include all/. 

regression.m:
- Performs pixelwise regression on emotional valence

regression_PCA.m:
- Uses PCA

### 3) Structural information

config/ contains scripts that read from a config.TOML file. Useful for adjusting naming, juggling different subject folders, etc. 
helpers/ contains helper functions


Overview of the study:
We are studying the effects of nostalgic and control songs on bodily sensation of emotion.

Participants take part in a Qualtrics survey through Prolific, and are asked to provide 4 songs which are nostalgic to them.

Then, 4 genre similar control songs are algorithmically produced per provided nostalgia song.

Participants are then shown either nostalgic or control songs, randomly:
- They are asked to provide metrics (Nostalgic rating, Positive vs. negative feelings, activation vs. deactivation).
- They are then asked to draw on a 2D image of a body, highlighting regions of activated (stored as positive values) and deactivated emotions (negative values)

This 2D pixel data is the heart of the study, and the focus of most of the analysis. 

One important caveat is that when taking the survey, each participant will have guaranteed 4 nostalgia songs (the participants select them)

However, the way that nostalgic songs are sourced, each nostalgic song may not have a corresponding control song. 
This is because a control song is are algorithmically similar to the nostalgia song, defined such that the subject is both familiar with but also not nostalgic. As expected, sometimes a corresponding control song won't be found. This is expected.

Therefore, one of the important preprocessing steps for the filtered subjects is to match the nostalgia and control trials.  

If a subject has at least 1 'pair', it is included in the preprocessed subfolder.
All subjects (within the specified cohort) are included 


The important subfolder structure is shown:
>> ls subjects\

.                                    SP                                   subject_list_preprocessed.csv        
..                                   US                                   subject_list_unfiltered.csv          
BR                                   all                                  
IN                                   preprocessing_remove_paired.csv      
JP                                   preprocessing_remove_unfiltered.csv  

where subject_list_preprocessed.csv contains a country-specified list of all subjects with at least one pair, unfiltered.csv is the same except it includes subjects without any pairs. 


>> ls subjects\US\

.             ..            preprocessed  subjects      unfiltered 

Where processed is a directory of all valid paired preprocessed.mat files and unfiltered is inclusive (i.e. a subject is included even if they don't have any control songs--- these participants are used for nostalgia based regression, among other scripts).
The subjects subfolder is the raw pixel data. Preprocessed and Unfiltered are ephemeral whereas subjects is permanent. So don't delete anything from subjects/ unless you know what you're doing)

An example is shown:
>> disp(load('subjects\US\preprocessed\mysubject_preprocessed.mat'))
            Nost2: [522×171 double]
            Nost3: [522×171 double]
            Nost4: [522×171 double]
            Cont2: [522×171 double]
            Cont3: [522×171 double]
            Cont4: [522×171 double]
    nostalgia_avg: [522×171 double]
      control_avg: [522×171 double]
      valid_pairs: [2 3 4]

Additionally, we also have a combined_data_all.csv that contains important information to be used. This lives in the project root and is created by preprocessing.m
