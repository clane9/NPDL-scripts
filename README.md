# NPDL-scripts

Functional MRI analysis scripts for the [Neuroplasticity and Development
Lab](http://sites.krieger.jhu.edu/bedny-lab/).

## Installation

- Clone the scripts directory to your machine:

```
git clone https://github.com/NPDL/NPDL-scripts
```

- Modify the configuration script: NPDL-config.sh.
- Source the configuration script in your shell startup file (e.g. in
  ~/.bashrc).

## Dependencies

Required (with recommended versions):

- FSL (5.0.9)
- Freesurfer (5.3.0)
- HCP Workbench (1.2.0)
- Mricron (2014-08-04)
- Python (2.7) [with docopt, matplotlib, nibabel, numpy, scipy, gdist]
- Imagemagick

Optional:

- FSL-Fix (1.062 beta)
  - R (>3.2.0) [with kernlab, ROCR, class, party, e1071, randomForest] 
  - MATLAB (R2014a)
- ICA-AROMA (0.3_beta)
- FSL PALM (alpha97)
