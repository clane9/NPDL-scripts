#!/bin/bash

# -----------------------------------------------------------------------------
# Template for making roi_extract batch job (assuming individual sub ROIs)
# -----------------------------------------------------------------------------

## Fill in your study directory.
study_dir=
cd $study_dir

## Modify job and log paths for your purposes.
job=Jobs/roi/roi_extract_01_071816/job.txt
log=Jobs/roi/roi_extract_01_071816/log.txt
# Overwrite job and log if they already exists.
rm $job $log 2>/dev/null

## Fill in list of subjects, separated by spaces and enclosed in quotes.
subs=""

## Fill in a bunch of yoked arrays. The ith postion in each array will
## correspond to the same ROI extraction analysis.
## Fill in the tasks, task-conditions, and conditions to exclude from extraction.
tasks=()
taskconds=("")
taskxconds=("")
## E.g.::
# taskconds=( "m nm nw drops resp" "MH ME NMH NME OR SR" )
# taskxconds=( "drops" "" )

## Fill in the nuisance covariates to include for each analysis.
taskcfds=("")
## E.g.::
# taskcfds=( "wm fdrms" "" )

## Fill in the roi names and hemis.
roinames=()
hemis=()

## Fill in the "extraction names". These will be used to name the output folders.
extractnames=()

# Loop through the subjects.
for sub in $subs; do
  # Set the extraction directory, and create it if it doesn't already exit.
  extract_dir=$sub/extract
  mkdir $extract_dir 2>/dev/null

  # Loop through the ROI extraction indices.
  for ((i=0; i<${#tasks[@]}; i++)); do
    # Extract all the info for this ROI from the yoked arrays.
    task=${tasks[i]}
    conds=${taskconds[i]}
    xconds=${taskxconds[i]}
    cfds=${taskcfds[i]}
    roiname=${roinames[i]}
    hemi=${hemis[i]}
    extractname=${extractnames[i]}
    
    # Look up preprocessing directories containing the functional data.
    preprocdirs=$(echo $sub/preproc/${task}_??.feat)
    # Skip subject if they don't have any preprocessing dirs.
    if [[ ${preprocdirs//\?/} != $preprocdirs ]]; then
      continue
    fi

    # Organize the list of functional data series.
    runs=
    runnames=
    for run in $preprocdirs; do
      # Find the data file.
      data=$run/$hemi.32k_fs_LR.surfed_data.func.gii
      # Find the confound covariates (if they exist).
      for cfd in $cfds; do
        cfdf=$run/art/${cfd}.confound.txt
        if [[ -f $cfdf ]]; then
          data=$data:$cfdf
        fi
      done
      runs="$runs $data"
      # Take the run basename, minux the .feat extension as the run name.
      # E.g. BSYN_S_01/preproc/bsyn_01.feat --> bsyn_01
      runnames="$runnames $(basename ${run%.feat})"
    done

    # Organize the timing file arguments.
    condargs=
    for cond in $conds; do
      timings=
      for run in $runnames; do
        # Note where timing files are assumed to live, and how they're assumed
        # to be named.
        timings="$timings $sub/timing/$run-$cond.txt"
      done
      condargs="$condargs --cond=\"$cond: $timings\""
    done
    
    # Find the roi mask.
    roif=$sub/roi/$roiname.$hemi.shape.gii
    
    # Set the output directory.
    outdir=$extract_dir/$extractname

    # Print the roi_extract job.
    # Note that all extraction modes are enabled by default.
    echo "roi_extract --mode=\"hrf fir classic\" \
      --X=\"$xconds\" --log=$log --roi=$roif \
      --runs=\"$runs\" \
      $condargs \
      --out=$outdir" >> $job
  done
done
