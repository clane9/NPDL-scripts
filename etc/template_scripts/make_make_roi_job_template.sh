#!/bin/bash

# -----------------------------------------------------------------------------
# Template for making make_roi batch job
# -----------------------------------------------------------------------------

## Fill in your study directory.
study_dir=
cd $study_dir

## Modify job and log paths for your purposes.
job=Jobs/roi/make_roi_01_071816/job.txt
log=Jobs/roi/make_roi_01_071816/log.txt
# Overwrite job and log if they already exists.
rm $job $log 2>/dev/null

## Fill in list of subjects, separated by spaces and enclosed in quotes.
subs=""

## Fill in a bunch of yoked arrays. The ith postion in each array will
## correspond to the same ROI.
## Fill in the tasks, designs, contrasts for the functional maps used to define each ROI.
tasks=()
designs=()
copes=()

## Fill in the search spaces.
searchs=()

## Fill in the ROI definition modes and methods.
modes=()
defmethods=("")
## E.g.:
# defmethods=( "-n 300" "-p 10" )

## Fill in the ROI names and hemis.
roinames=()
hemis=()

# Loop through the subjects.
for sub in $subs; do
  # Individual subject ROIs will be saved to the subject's ROI folder.
  # Make the folder if it doesn't already exist.
  roi_dir=$sub/roi
  mkdir $roi_dir 2>/dev/null
  
  # Loop through the ROI indices.
  for ((i=0; i<${#tasks[@]}; i++)); do
    # Extract all the info for this ROI from the yoked arrays.
    task=${tasks[i]}
    design=${designs[i]}
    cope=${copes[i]}
    search=${searchs[i]}
    mode=${modes[i]}
    defmethod=${defmethods[i]}
    roiname=${roinames[i]}
    hemi=${hemis[i]}

    # Look up the subject's zstat. Note the assumed naming convention.
    zstat=$sub/firstlevel/${task}-${design}.${hemi}.ffx/zstat${cope}.func.gii
    
    # Print the make_roi job.
    echo "make_roi $mode --search $search $defmethod \
      $zstat $roi_dir/${roiname}.${hemi}.csv $roi_dir/${roiname}.${hemi}" >> $job
  done
done
