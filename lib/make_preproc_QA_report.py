#!/usr/bin/env python

"""
Usage: make_preproc_QA_report.py <preproc-dir>
"""

from docopt import docopt
ARGS = docopt(__doc__)

import os
import numpy as np
from scipy.stats import pearsonr

outdir = ARGS['<preproc-dir>']
fillers = dict()

# Look up basic info
command = open('{}/command.txt'.format(outdir)).read().strip()
fillers['command'] = command

sub = command.split()[-3]
run = os.path.basename(command.split()[-2]).split('.')[0]
fillers['subject'] = sub
fillers['run_name'] = run

# Fill in image paths
fillers['raw_gif'] = 'raw_func_data.gif'
fillers['clean_gif'] = 'filtered_func_data_clean.gif'

fillers['temp_sd'] = 'art/filtered_func_tSD.png'
fillers['temp_snr'] = 'art/filtered_func_tSNR.png'

fillers['global_sig'] = 'mc/globsig.png'
fillers['global_sig_by_tissue'] = 'art/gm-wm-csf.confound.png'

fillers['mot_trans_params'] = 'mc/trans.png'
fillers['mot_rot_params'] = 'mc/rot.png'

fillers['fdrms'] = 'art/fdrms.png'
fillers['dvars'] = 'art/dvars.png'

fillers['surf_outline'] = 'surfreg/surf_outline.png'

# Load time-series statistics
gm = np.genfromtxt('{}/art/gm.values.txt'.format(outdir))
wm = np.genfromtxt('{}/art/wm.values.txt'.format(outdir))

fillers['gm_sd'] = np.std(gm)
fillers['wm_sd'] = np.std(wm)
fillers['gm_wm_rsqrd'] = pearsonr(gm, wm)[0]**2
fillers['gm_wm_snr'] = np.mean(gm)/np.std(wm)

fdrms = np.genfromtxt('{}/art/fdrms.values.txt'.format(outdir))
fillers['mean_fd'] = np.mean(fdrms)
fillers['95th_fd'] = np.percentile(fdrms, .95)
fillers['gt_02_fd'] = np.sum(fdrms > 0.2)
fillers['gt_05_fd'] = np.sum(fdrms > 0.5)
fillers['gt_10_fd'] = np.sum(fdrms > 1.0)
fillers['gt_15_fd'] = np.sum(fdrms > 1.5)
fillers['gt_20_fd'] = np.sum(fdrms > 2.0)

# Read surface coverage
coverage = open('{}/surf_coverage.csv'.format(outdir)).read().split('\n')[1:]
i=0
for lobe in ['front', 'temp', 'occ', 'pariet']:
  for hemi in ['lh', 'rh']:
    fillers['cover_{}_{}'.format(hemi, lobe)] = float(coverage[i].split(',')[2])
    i += 1

# Populate report
template = open('{}/etc/preproc_QA_report_template.html'.format(os.environ['NPDL_SCRIPT_DIR'])).read()
html = template.format(**fillers)
f = open('{}/report_QA.html'.format(outdir), 'w')
f.write(html)
f.close()
