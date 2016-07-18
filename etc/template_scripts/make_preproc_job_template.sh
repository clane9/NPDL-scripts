#!/bin/bash

# -----------------------------------------------------------------------------
# Template for making preproc batch job
# -----------------------------------------------------------------------------

## Fill in your study directory.
study_dir=
cd $study_dir

## Modify job and log paths for your purposes.
job=Jobs/preproc/preproc_01_071816/job.txt
log=Jobs/preproc/preproc_01_071816/log.txt
# Overwrite job and log if they already exists.
rm $job $log 2>/dev/null

## Fill in list of subjects, separated by spaces and enclosed in quotes.
subs=""

## Fill in list tasks.
tasks=""

## Fill in preprocessing options.
opts="--log $log"

# Loop through subs, tasks, and runs to generate job file.
# NOTE: assumes that raw functional paths look like $sub/raw/${task}_??
for sub in $subs; do
  # Make preproc dir if doesn't already exist.
  mkdir $sub/preproc 2>/dev/null
  for task in $tasks; do
    # Glob raw functionals.
    for rawfunc in $sub/raw/${task}_??.nii.gz; do
      # Determine the outdir from the basename of the functional file.
      # Basename of outdir becomes: ${task}_??
      outdir=$sub/preproc/$(basename ${rawfunc%.nii.gz})
      # Print command-line to job file
      echo preproc $opts $sub $rawfunc $outdir >> $job
    done
  done
done
