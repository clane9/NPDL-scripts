#!/bin/bash

# -----------------------------------------------------------------------------
# Template for making firstlevel batch job
# -----------------------------------------------------------------------------

## Fill in your study directory.
study_dir=
cd $study_dir

## Modify job and log paths for your purposes.
job=Jobs/firstlevel/firstlevel_01_071816/job.txt
log=Jobs/firstlevel/firstlevel_01_071816/log.txt
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

# List the conditions for each task/design pair. This is array is also paired
# with the $tasks and $designs array. However here the entries are lists
# (enclosed in quotes and separated by spaces) rather than individual workds.
task_conds=( "" )
## E.g.:
# task_conds=( "m nm nw resp" "MH ME NME NMH OR SR" "MH ME NME NMH OR SR" )

## List the names of the nuisance covariates to add to the model.
cfds="fdrms wm csf"

## List the firstlevel options for each task/design pair. Here each entry is a
## string enclosed in quotes.
task_opts=( "--log $log" )

# Loop through the tasks, subs, runs, and hemispheres to generate job file.
# First, loop through the task array indices.
for ((i=0; i<${#tasks[@]}; i++)); do
  # Retrieve the task, design name, conditions, and options from their
  # respective arrays, based on the index.
  task=${tasks[i]}
  design_name=${designs[i]}
  conds=${task_conds[i]}
  opts=${task_opts[i]}
  # Find path to design file, assuming standard convention for its location and
  # file name.
  design=Designs/${task}-${design_name}.fsf
  # Now loop through each sub.
  for sub in $subs; do
    # Make a firstlevel dir if it doesn't already exit.
    mkdir -p $sub/firstlevel 2>/dev/null
    # Loop through all runs for this subject and task.
    for preproc_dir in $sub/preproc/${task}_??.feat; do
      # Look up the run name, e.g. bsyn_01.
      run_name=$(basename ${preproc_dir%.feat})
      # Fetch list of timing files for this sub and run.
      # Timing files assumed to be inside subject's timing folder, and follow
      # standard naming convention.
      evs=
      for cond in $conds; do
        evs="$evs $sub/timing/${run_name}-${cond}.txt"
      done
      # Trim off leading space.
      evs=${evs:1} 
      # Fetch list of confound covariates.
      cfdfs=
      for cfd in $cfds; do
        # Covariates assumed to be in art folder, within preprocessed output dir.
        cfdf=$preproc_dir/art/$cfd.confound.txt
        # Add the file to the list of confounds if it exists.
        # NOTE: confound list separated by commas.
        if [[ -f $cfdf ]]; then
          cfdfs="$cfdfs,$cfdf"
        fi
      done
      # Trim off leading space.
      cfdfs=${cfdfs:1}
      # Finally, create a separate job for each hemi.
      for hemi in lh rh; do
        # Look up surface data in preprocessed dir.
        data=$preproc_dir/$hemi.32k_fs_LR.surfed_data.func.gii
        # Look up subjects 32k_fs_LR midthickness surface.
        surf=SurfAnat/$sub/surf/$hemi.32k_fs_LR.midthickness.surf.gii
        # Determine name of output dir.
        outdir=$sub/firstlevel/${run_name}-${design_name}.$hemi.glm
        # Print command-line to job file.
        echo "firstlevel --cfd $cfdfs $opts $data $surf $design \"$evs\" $outdir" >> $job
      done
    done
  done
done
