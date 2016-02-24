#!/bin/bash

# helper functions for NPDL

command_check () {
  if [[ ${PIPESTATUS[0]} != 0 ]]; then
    echo "ERROR: $1 failed." >&2 
    kill -INT $$
  fi
}

checksurf() {
  if [[ $# == 0 || $1 == -h || $1 == --help ]]; then
    echo "Usage: checksurf <subj>"
    echo
    echo "Load recon-all output for given subject in $SUBJECTS_DIR using freeview."
    return
  fi
  if [[ $# != 1 ]]; then
    echo "ERROR: Incorrect number of arguments." >&2
    return 1
  fi
  subj=$1
  subdir=$SUBJECTS_DIR/$subj
  if [[ ! -d $subdir ]]; then
    echo "ERROR: The subject $subj does not exist." >&2
    return 1
  fi
  freeview \
    -v \
    $subdir/mri/orig.mgz:visible=0 \
    $subdir/mri/brainmask.mgz \
    -f \
    $subdir/surf/lh.white:edgecolor=blue:edgethickness=2 \
    $subdir/surf/rh.white:edgecolor=blue:edgethickness=2 \
    $subdir/surf/lh.pial:edgecolor=green:edgethickness=2 \
    $subdir/surf/rh.pial:edgecolor=green:edgethickness=2 \
    $subdir/surf/lh.inflated:edgethickness=0:visible=0 \
    $subdir/surf/rh.inflated:edgethickness=0:visible=0
  return
}

checkffx () {
  if [[ $# == 0 ]]; then
    echo "Usage: checkffx [options] <ffxdir>"
    return
  elif [[ $1 == -h || $1 == --help ]]; then
    echo "Usage: checkffx [options] <ffxdir>"
    echo
    echo "View fixed-effects results tksurfer."
    echo
    echo "Arguments:"
    echo "  <ffxdir>    Path to fixed-effect directory."
    echo
    echo "Options:"
    echo "  --copes=<copes>    List of copes, separated by commas (e.g. 4,5,6)."
    echo "                     [default: all]"
    echo "  --subj=<subj>      Freesurfer subject to load. [default: 32k_fs_LR]"
    echo "  --hemi=<hemi>      lh or rh. [default: infer from <ffxdir>]."
    echo "  --surf=<surf>      Anatomical surface. [default: hcp_very_inflated]"
    echo "  --thr=<min,max>    Min, max zstat overlay threshold. [default: 2.33,7]"
    return
  fi

  local copes=
  local subj=32k_fs_LR
  local hemi=
  local surf=hcp_very_inflated
  local thr="2.33 7"

  while [[ $1 == -* ]]; do
    case $1 in
      --copes=*,*)
        copes=${1#*=}
        copes=${copes//,/ }
        shift
        ;;
      --subj=*)
        subj=${1#*=}
        shift
        ;;
      --hemi=*)
        hemi=${1#*=}
        shift
        ;;
      --surf=*)
        surf=${1#*=}
        shift
        ;;
      --thr=*,*)
        thr=${1#*=}
        thr=${thr//,/ }
        shift
        ;;
      *)
        echo "ERROR: Unrecognized flag $1." >&2
        return 1
    esac
  done

  if [[ $# != 1 ]]; then
    echo "ERROR: Exactly 1 argument required." >&2
    return 1
  fi
  
  local ffxdir=${1%/}

  local zstats
  local overlay_str
  
  if [[ -z $hemi ]]; then
    hemi=`basename $ffxdir | grep -oh '\.[lr]h\.ffx$'`
    hemi=${hemi:1:2}
  fi
  
  if [[ -z $copes ]]; then
    zstats=`echo $ffxdir/zstat*.func.gii`
  else
    zstats=
    for c in $copes; do
      zstats="$zstats $ffxdir/zstat$c.func.gii"
    done
  fi

  if (( `echo $zstats | wc -w` >= 10 )); then
    echo "WARNING: Can only load max 9 contrasts." >&2
    zstats=`echo $zstats | cut -d " " -f 1-9`
  fi

  overlay_str=
  for z in $zstats; do
    overlay_str="$overlay_str -overlay $z"
  done
  
  echo "tksurfer $subj $hemi $surf $overlay_str -fminmax $thr"
  tksurfer $subj $hemi $surf $overlay_str -fminmax $thr
  return
}

odd_or_even () {
    if [ "$#" = "0" -o "$1" = "-h" -o "$1" = "--help" ]; then
        echo "Usage: odd_or_even (--odd | --even) <item>..."
        echo
        echo "Print either the odd or even items from the given list"
        echo
        return
    fi
    if [ "$1" = "--odd" ]; then
        test=1
    elif [ "$1" = "--even" ]; then
        test=0
    else
        echo "ERROR: Bad arguments."
        return 1
    fi
    shift
    odds_or_evens=
    i=1
    while [ -n "$1" ]; do
        if [ "$(($i % 2))" = "$test" ]; then
            odds_or_evens="$odds_or_evens $1"
        fi
        shift
        i=$(($i + 1))
    done
    echo $odds_or_evens
    return
}

beta_calc () {
    if [ "$#" = "0" -o "$1" = "-h" -o "$1" = "--help" ]; then
        echo "Usage: beta_calc <subject> <hemi> <label> <task> <con-list>"
        echo
        echo "Calculate average beta within a freesurfer label for given"
        echo "subject, task, contrast. Label must be in fsaverage space."
        echo "Function must be called within study directory"
        echo
        echo "Arguments:"
        echo "    <con-list>    List of contrast numbers enclosed in quotes"
        echo "                  and separated by spaces. (e.g. \"6 7 8\")"
        echo
        return
    fi
    if [ "$#" != "5" ]; then
        echo "ERROR: incorrect number of arguments"
        return 1
    fi
    subj=$1
    hemi=$2
    label=`readlink -f $3`
    task=$4
    cons=$5
    if [ ! -f "$label" ]; then
        echo "ERROR: $label does not exist."
        return 1
    fi
    copes=
    for con in $cons; do
        cope=$subj/FE/$task.$hemi/cope$con/cope1.nii.gz
        cope=`readlink -f $cope`
        if [ ! -f "$cope" ]; then
            echo "ERROR: $cope does not exist."
            return 1
        fi
        copes="$copes $cope"
    done
    betas=
    for cope in $copes; do
        labelmask=`mktemp -u /tmp/labelmaskXXX`.nii.gz
        trglabel=`mktemp -u /tmp/labelXXX`.label
        mri_label2label --srclabel $label --s fsaverage --hemi $hemi --trglabel $trglabel --outmask $labelmask --regmethod surface > /dev/null 2>&1
        copemask=`mktemp -u /tmp/copemaskXXX`.nii.gz
        fslmaths $cope -mul $labelmask $copemask > /dev/null 2>&1
        betas="$betas `fslstats $copemask -M`"
    done
    fmtstring="%s\t"
    for beta in $betas; do
        fmtstring="${fmtstring}%.2f\t"
    done
    fmtstring="$fmtstring\n"
    out="$subj $betas"
    printf "$fmtstring" $out
    return
}

percentroi () {
  if [[ $# == 0 || $1 == -h || $1 == --help ]]; then
    echo
    echo "Usage: percentroi <perc> <surf> <mask> <stat> <out>"
    echo
    echo "Make gifti ROI containing the top X % stat voxels within mask."
    echo "Inputs should be in gifti format. Prints out min and max of ROI."
    echo
    return
  fi

  if [[ $# != 5 ]]; then
    echo "ERROR: 5 arguments required." >&2
    return
  fi

  local perc=$1
  local surf=$2
  local mask=$3
  local stat=$4
  local out=$5

  perc=`echo "100-$perc" | bc -l`
  command_check bc

  for f in $surf $mask $stat; do
    if [[ ! -f $f ]]; then
      echo "ERROR: $f does not exist." >&2
      return
    fi
  done

  local tmpdir=`mktemp -d /tmp/toptenroi-XXX`
  # shift values up 1000 to deal with issues when threshold is negative
  wb_command -metric-math "(stat+1000)*mask" $tmpdir/maskedstat.func.gii \
    -var stat $stat -var mask $mask >/dev/null 2>&1
  command_check "stat masking, scaling"
  wb_command -metric-convert -to-nifti $tmpdir/maskedstat.func.gii \
    $tmpdir/maskedstat.nii.gz
  command_check "masked stat conversion to nifti"
  
  local maskedstat=$tmpdir/maskedstat.nii.gz
  local thresh=`fslstats $maskedstat -P $perc`
  command_check "fslstats -P"
  local max=`fslstats $maskedstat -R | cut -d " " -f 2`
  command_check "fslstats -R"
  wb_command -metric-math "(maskedstat >= $thresh)" $out \
    -var maskedstat $tmpdir/maskedstat.func.gii >/dev/null 2>&1
  command_check "roi creation"
  thresh=`echo "$thresh - 1000" | bc -l`
  max=`echo "$max - 1000" | bc -l`
  if (( `echo "$thresh <= 0" | bc -l` == 1 )); then
    echo "WARNING: percent threshold $thresh <= 0." >&2
  fi
  echo $thresh $max
  rm -r $tmpdir
  return
}

threshroi () {
  if [[ $# == 0 || $1 == -h || $1 == --help ]]; then
    echo
    echo "Usage: threshroi [options] <surf> <mask> <zstat> <out>"
    echo
    echo "Make gifti ROI containing the vertices above a given threshold within a mask."
    echo "Inputs should be in gifti format."
    echo
    echo "Options:"
    echo "  --thr=<z-val>    Z stat threshold. [default=2.575]"
    return
  fi
  
  # declare local variables
  local thr
  local surf
  local mask
  local zstat
  local out
  local tmpdir
  local vox_count

  # default
  thr=2.575

  while [[ $1 == -* ]]; do
    case $1 in
      --thr=*)
        thr=${1#*=}
        shift
        ;;
      *)
        echo "ERROR: Unrecognized flag $1."
        return 1
        ;;
    esac
  done

  surf=$1
  mask=$2
  zstat=$3
  out=$4

  tmpdir=`mktemp -d /tmp/threshroi-XXX`
  wb_command -metric-convert -to-nifti $mask $tmpdir/mask.nii.gz
  command_check "mask conversion to nifti" 
  wb_command -metric-convert -to-nifti $zstat $tmpdir/zstat.nii.gz
  command_check "zstat conversion to nifti"
  
  mask=$tmpdir/mask.nii.gz
  zstat=$tmpdir/zstat.nii.gz
  fslmaths $zstat -mas $mask -thr $thr -bin $tmpdir/roi.nii.gz
  command_check "fslmaths masking, thresholding"
  wb_command -metric-convert -from-nifti $tmpdir/roi.nii.gz $surf $out
  command_check "roi conversion to gifti"
  vox_count=`fslstats $tmpdir/roi.nii.gz -V | cut -d " " -f 1`
  if (( $vox_count < 20 )); then
    echo "WARNING: Roi contains fewer than 20 vertices." >&2
  fi
  echo $vox_count
  rm -r $tmpdir
  return
}

latcheck () {
  if [[ $# == 0 ]]; then
    echo "Usage: latcheck [options] <lh-stat> <rh-stat>"
    return
  elif [[ $1 == -h || $1 == --help ]]; then
    echo "Usage: latcheck [options] <lh-stat> <rh-stat>"
    echo
    echo "Compute laterality index."
    echo
    echo "Options:"
    echo "  --mode=(mass|count)    Calculate activation mass or"
    echo "                         count. [default: mass]"
    echo "  --thr=<val>            Stat threshold. [default: 2.3]"
    echo "  --masks=<lh>,<rh>      Masks to restrict index to."
    echo
    return
  fi
  
  # defaults
  local hemis=( lh rh )
  local masses=( 0.0 0.0 )
  local mode=mass
  local thr=2.3
  local masks=

  while [[ $1 == -* ]]; do
    case $1 in
      --mode=*)
        mode=${1#*=}
        shift
        ;;
      --thr=*)
        thr=${1#*=}
        shift
        ;;
      --masks=*)
        masks=${1#*=}
        masks=( ${masks//,/ } )
        shift
        ;;
      *)
        echo "ERROR: Unrecognized flag ${1%=*}." >&2
        return 1
        ;;
    esac
  done
  
  if [[ $mode != mass && $mode != count ]]; then
    echo "ERROR: Bad mode arg ($mode)." >&2
    return 1
  fi

  local numre='^-?[0-9]+([.][0-9]+)?$'
  if [[ ! $thr =~ $numre ]]; then
    echo "ERROR: thr ($thr) not a number." >&2
    return 1
  fi
  
  if [[ -n $masks ]]; then
    if [[ ${#masks[@]} != 2 ]]; then
      echo "ERROR: masks arg ($masks) has bad format." >&2
      return 1
    fi
    for mask in ${masks[@]}; do
      if [[ ! -f $mask ]]; then
        echo "ERROR: mask $mask does not exist." >&2
        return 1
      fi
    done
  fi
  
  if [[ $# != 2 ]]; then
    echo "ERROR: Incorrect number of arguments ($#)." >&2
    return 1
  fi
  local stats=( $1 $2 )
  for stat in ${stats[@]}; do
    if [[ ! -f $stat ]]; then
      echo "ERROR: stat $stat does not exist." >&2
      return 1
    fi
  done
  
  local tmpdir=`mktemp -d /tmp/latcheck-XXX`
  for i in 0 1; do
    local hemi=${hemis[i]}
    local mask=${masks[i]}
    local stat=${stats[i]}
    local expression="(stat >= $thr)"
    local vararg="-var stat $stat"
    if [[ -n $mask ]]; then
      expression="$expression * mask"
      vararg="$vararg -var mask $mask"
    fi
    if [[ $mode == mass ]]; then
      expression="stat * $expression"
    fi
    wb_command -metric-math "$expression" $tmpdir/stat.$hemi.func.gii $vararg >/dev/null 2>&1
    command_check "stat thresholding"
    masses[i]=`wb_command -metric-vertex-sum $tmpdir/stat.$hemi.func.gii` >/dev/null 2>&1
    command_check "vertex sum"
  done
  local LI=`echo "(${masses[0]} - ${masses[1]})/(${masses[0]} + ${masses[1]})" | bc -l`
  LI=`printf '%.3f' $LI`
  echo $LI
  rm -r $tmpdir
  return
}

latcheck2 () {
  if [[ $# == 0 ]]; then
    echo "Usage: latcheck2 [options] <lh-stat> <rh-stat>"
    return
  elif [[ $1 == -h || $1 == --help ]]; then
    echo "Usage: latcheck [options] <lh-stat> <rh-stat>"
    echo
    echo "Compute laterality counts for lh and rh."
    echo
    echo "Options:"
    echo "  --mode=(mass|count)    Calculate activation mass or"
    echo "                         count. [default: mass]"
    echo "  --thr=<val>            Stat threshold. [default: 2.3]"
    echo "  --masks=<lh>,<rh>      Masks to restrict index to."
    echo
    return
  fi
  
  # defaults
  local hemis=( lh rh )
  local masses=( 0.0 0.0 )
  local mode=mass
  local thr=2.3
  local masks=

  while [[ $1 == -* ]]; do
    case $1 in
      --mode=*)
        mode=${1#*=}
        shift
        ;;
      --thr=*)
        thr=${1#*=}
        shift
        ;;
      --masks=*)
        masks=${1#*=}
        masks=( ${masks//,/ } )
        shift
        ;;
      *)
        echo "ERROR: Unrecognized flag ${1%=*}." >&2
        return 1
        ;;
    esac
  done
  
  if [[ $mode != mass && $mode != count ]]; then
    echo "ERROR: Bad mode arg ($mode)." >&2
    return 1
  fi

  local numre='^-?[0-9]+([.][0-9]+)?$'
  if [[ ! $thr =~ $numre ]]; then
    echo "ERROR: thr ($thr) not a number." >&2
    return 1
  fi

  if [[ -n $masks && ${#masks[@]} != 2 ]]; then
    echo "ERROR: masks arg ($masks) has bad format." >&2
    return 1
  fi
  
  if [[ $# != 2 ]]; then
    echo "ERROR: Incorrect number of arguments ($#)." >&2
    return 1
  fi
  local stats=( $1 $2 )
  
  local tmpdir=`mktemp -d /tmp/latcheck-XXX`
  for i in 0 1; do
    local hemi=${hemis[i]}
    local mask=${masks[i]}
    local stat=${stats[i]}
    local expression="(stat >= $thr)"
    local vararg="-var stat $stat"
    if [[ -n $mask ]]; then
      expression="$expression * mask"
      vararg="$vararg -var mask $mask"
    fi
    if [[ $mode == mass ]]; then
      expression="stat * $expression"
    fi
    wb_command -metric-math "$expression" $tmpdir/stat.$hemi.func.gii $vararg >/dev/null 2>&1
    command_check "stat thresholding"
    masses[i]=`wb_command -metric-vertex-sum $tmpdir/stat.$hemi.func.gii` >/dev/null 2>&1
    command_check "vertex sum"
  done
  local masstotal=`echo "${masses[0]} + ${masses[1]}" | bc -l`
  local masstest=`echo "$masstotal > 0" | bc -l`
  if [[ $masstest == 1 ]]; then
    local lprop=`echo "${masses[0]}/$masstotal" | bc -l`
    local LI=`echo "(${masses[0]}-${masses[1]})/$masstotal" | bc -l`
  else
    local lprop=NaN
    local LI=NaN
  fi
  echo $LI $lprop $masstotal 
  rm -r $tmpdir
  return
}

label2mask () {
  if [[ $# == 0 || $1 == -h || $1 == --help ]]; then
    echo "Usage: label2mask [options] <label> <mask>"
    echo 
    echo "Convert .label to .gii"
    echo 
    echo "Options:"
    echo "  --sub <subject>    [default: 32k_fs_LR]"
    echo "  --hemi <hemi>      [default: lh]"
    echo 
    return
  fi

  sub=32k_fs_LR
  hemi=lh

  while [[ $1 == -* ]]; do
    case $1 in
      --sub)
        sub=$2
        shift
        shift
        ;;
      --hemi)
        hemi=$2
        shift
        shift
        ;;
      *)
        echo "ERROR: Unrecognized flag $1." >&2
        return 1
        ;;
    esac
  done

  if [[ $# != 2 ]]; then
    echo "ERROR: need two args." >&2
    return
  fi

  label=$1
  mask=$2
  tmplabel=`mktemp /tmp/labelXXX`
  mri_label2label --srclabel $label --trglabel $tmplabel --s $sub --hemi $hemi --regmethod surface --outmask $mask >/dev/null 2>&1
  rm $tmplabel
  return
}

takesnap () {
  if [[ $# == 0 ]]; then
    echo "Usage: takesnap [options] <subj> <hemi> <surf> <view> <out-png>"
    return
  elif [[ $1 == -h || $1 == --help ]]; then
    echo "Usage: takesnap [options] <subj> <hemi> <surf> <view> <out-png>"
    echo
    echo "Take a snapshot of a surface & overlay using freeview."
    echo
    echo "Arguments:"
    echo "  <subj>        Freesurfer subject in $SUBJECTS_DIR"
    echo "                (e.g. 32k_fs_LR)."
    echo "  <hemi>        lh or rh."
    echo "  <surf>        Anatomical surface to load (e.g. hcp_very_inflated)."
    echo "  <view>        lat, med, inf, sup, post, or front."
    echo "  <out-png>     Path to output png."
    echo
    echo "Options:"
    echo "  --ov=<overlay>     Statistical overlay to load."
    echo "  --annot=<annot>    Annotation file to load."
    echo "  --thr=<min,max>    Min, max threshold for overlay. [default: 2.33,7.0]"
    echo "  --size=<l,w>       Size of freeview window/image. [default: 800,575]"
    echo "  --zoom=<frac>      Zoom fraction. [default: 1.75]"
    return
  fi
  
  local thr=2.33,7.0
  local size="800 575"
  local zoom=1.75
  local overl=
  local annot=
  
  while [[ $1 == -* ]]; do
    case $1 in
      --ov=*)
        overl=${1#*ov=}
        shift
        ;;
      --annot=*)
        annot=${1#*annot=}
        shift
        ;;
      --thr=*,*)
        thr=${1#*thr=}
        shift
        ;;
      --size=*,*)
        size=${1#*size=}
        size=${size//,/ }
        shift
        ;;
      --zoom=*)
        zoom=${1#*zoom=}
        shift
        ;;
      *)
        echo "ERROR: Unrecognized flag $1." >&2
        return 1
        ;;
    esac
  done

  if [[ $# != 5 ]]; then
    echo "ERROR: 5 positional arguments required." >&2
    return 1
  fi
  
  local subj=$1
  local hemi=$2
  local surf=$3
  local view=$4
  local out=$5

  local surff=$SUBJECTS_DIR/$subj/surf/$hemi.$surf
  local make_lat_ops=( "-cam Azimuth 0" "-cam Azimuth 180" )
  
  local cam_ops=( ",Azimuth 180" "Azimuth 180," "Elevation -90,Elevation -90" "Elevation 90,Elevation 90" "Azimuth 90,Azimuth 90" "Azimuth -90,Azimuth -90" )
  
  local cam_op
  case $view in
    lat)
      cam_op=${cam_ops[0]}
      ;;
    med)
      cam_op=${cam_ops[1]}
      ;;
    inf)
      cam_op=${cam_ops[2]}
      ;;
    sup)
      cam_op=${cam_ops[3]}
      ;;
    post)
      cam_op=${cam_ops[4]}
      ;;
    front)
      cam_op=${cam_ops[5]}
      ;;
    *)
      echo "ERROR: bad view argument." >&2
      return 1
      ;;
  esac

  case $hemi in
    lh)
      cam_op=${cam_op%,*}
      ;;
    rh)
      cam_op=${cam_op#*,}
      ;;
    *)
      echo "ERROR: bad hemi argument." >&2
      return 1
      ;;
  esac
  
  local ovarg=
  if [[ -n $overl ]]; then
    ovarg=":overlay=$overl:overlay_threshold=$thr"
  fi
  if [[ -n $annot ]]; then
    ovarg="$ovarg:annot=$annot"
  fi
  freeview -viewport 3d -viewsize $size \
    -f $surff:edgethickness=0$ovarg \
    -cam Azimuth 0 $cam_op -zoom $zoom -ss $out >/dev/null 2>&1

  command_check "freeview snapshot $subj $hemi $view"
  return
}

imgtrim () {
  if [[ $# == 0 ]]; then
    echo "imgtrim [Options] <img> <out-img>"
    return 0
  elif [[ $1 == -h || $1 == --help ]]; then
    echo "imgtrim [Options] <img> <out-img>"
    echo
    echo "Trim background to fit image. Optionally make bg transparent."
    echo
    echo "Arguments:"
    echo "  <img>         Path to input image."
    echo "  <out-img>     Path to output image. Use extension to specify format."
    echo
    echo "Options:"
    echo "  --no-bg=<bg-color>    Make background transparent. Accepts the same"
    echo "                        color fomats as ImageMagick (e.g. 'white',"
    echo "                        '#00ff00', 'rgb(255,0,0)')"
    return 0
  fi
  
  local bgcolor=
  local rembgstr=

  while [[ $1 == -* ]]; do
    case $1 in
      --no-bg=*)
        bgcolor=${1#--no-bg=}
        shift
        ;;
      *)
        echo "ERROR: Unrecognized flag $1." >&2
        return 1
        ;;
    esac
  done

  if [[ $# != 2 ]]; then
    echo "ERROR: Incorrect number of args." >&2
    return 1
  fi
  
  local img=$1
  local outimg=$2
  if [[ -n $bgcolor ]]; then
    rembgstr="-alpha set -channel RGBA -fuzz 1% \
      -fill none -floodfill +0+0 $bgcolor"
  fi
  
  convert $img $rembgstr -trim $outimg
}

make_data_gif () {
  if [[ $# == 0 || $1 == -h || $1 == --help ]]; then
    echo "make_data_gif <func-data> <out-gif>"
    echo
    echo "Make an animated gif for one run of functional data."
    return
  fi

  if [[ $# != 2 ]]; then
    echo "ERROR: Incorrect number of args." >&2
    return 1
  fi

  local func=$1
  local outgif=$2
  local tmpdir=`mktemp -d /tmp/data-gif-XXX`

  fslsplit $func $tmpdir/split-

  for frame in $tmpdir/split-*; do
    local img=${frame/.nii.gz/.png}
    slicer $frame -u -a $img
    local tr_num=$(echo $img | sed 's@\(.*split-\)\(.*\)\(\.png\)@\2@')
    convert $img -background black -fill white label:$tr_num \
      -gravity Center -append $img
  done

  convert -delay 10 -loop 0 $tmpdir/split-*.png $outgif
  rm -r $tmpdir
}

export -f command_check checksurf checkffx odd_or_even beta_calc threshroi latcheck percentroi label2mask takesnap imgtrim latcheck2 make_data_gif
