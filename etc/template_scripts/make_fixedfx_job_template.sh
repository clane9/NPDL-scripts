#!/bin/bash

# -----------------------------------------------------------------------------
# Template for making fixedfx batch job
# -----------------------------------------------------------------------------

## Fill in your study directory.
study_dir=
cd $study_dir

## Modify job and log paths for your purposes.
job=Jobs/fixedfx/fixedfx_01_071816/job.txt
log=Jobs/fixedfx/fixedfx_01_071816/log.txt
# Overwrite job and log if they already exists.
rm $job $log 2>/dev/null

## Fill in list of subjects, separated by spaces and enclosed in quotes.
subs=""

## Fill in array of tasks and designs, separated by spaces and enclosed in
## parantheses. These are paired arrays of equal length; the ith task should
## correspond to the ith design. You can have multiple instances of the same
## task in the $tasks variable, if you have several different designs for
## the task. Having different designs allows you to try out different analysis
## strategies for the same task. 
tasks=(  )
designs=( )
## E.g.:
# tasks=( bsyn smath smath )
# designs=( canon_hrf canon_hrf gamma_hrf ) 

# Loop through the tasks, subs, and hemispheres to generate job file.
# First, loop through the task array indices.
for ((i=0; i<${#tasks[@]}; i++)); do
  task=${tasks[i]}
  design_name=${designs[i]}
  for sub in $subs; do
    for hemi in lh rh; do
      # Note the assumed naming convention for firstlevel results.
      glmdirs=$(echo $sub/firstlevel/${task}_??-${design_name}.$hemi.glm)
      outdir=$sub/firstlevel/${task}-${design_name}.$hemi.ffx
      # Print job to job file.
      echo "fixedfx --log $log $hemi $outdir $glmdirs" >> $job
    done
  done
done
