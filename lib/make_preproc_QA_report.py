#!/usr/bin/env python

"""
Usage: make_preproc_QA_report.py <preproc-dir>
"""

from docopt import docopt
ARGS = docopt(__doc__)

import os
import numpy as np
from scipy.stats import pearsonr
import subprocess as sp

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
fillers['95th_fd'] = np.percentile(fdrms, 95)
fillers['gt_02_fd'] = np.sum(fdrms > 0.2)
fillers['gt_05_fd'] = np.sum(fdrms > 0.5)
fillers['gt_10_fd'] = np.sum(fdrms > 1.0)
fillers['gt_15_fd'] = np.sum(fdrms > 1.5)
fillers['gt_20_fd'] = np.sum(fdrms > 2.0)

# Read surface coverage
dir_32k = '{}/32k_fs_LR'.format(os.environ['SUBJECTS_DIR'])
lobedir = '{}/label/PALS_B12_Lobes/masks'.format(dir_32k)
lobes = 'FRONTAL', 'TEMPORAL', 'PARIETAL', 'OCCIPITAL'
for lobe in lobes:
  for hemi in ['lh', 'rh']:
    surf = '{}/surf/{}.midthickness.surf.gii'.format(dir_32k, hemi)
    lobe_mask = '{}/{}.LOBE.{}.shape.gii'.format(lobedir, hemi, lobe)
    data_mask = '{}/{}.32k_fs_LR.mask.shape.gii'.format(outdir, hemi)
    cmnd = 'wb_command -metric-vertex-sum {} -integrate {}'.format(lobe_mask, surf)
    lobe_size = float(sp.check_output(cmnd, shell=True))
    cmnd = 'wb_command -metric-vertex-sum {} -integrate {} -roi {}'.format(data_mask, surf, lobe_mask)
    lobe_cover = float(sp.check_output(cmnd, shell=True))
    fillers['cover_{}_{}'.format(hemi, lobe)] = lobe_size - lobe_cover

# Populate report
template = open('{}/etc/preproc_QA_report_template.html'.format(os.environ['NPDL_SCRIPT_DIR'])).read()
html = template.format(**fillers)
f = open('{}/report_QA.html'.format(outdir), 'w')
f.write(html)
f.close()

# Write summary stats out as csv also
csv_filler_keys = ['subject', 'run_name', 'gm_sd', 'wm_sd', 'gm_wm_rsqrd',
                   'gm_wm_snr', 'mean_fd', '95th_fd', 'gt_02_fd', 'gt_05_fd',
                   'gt_10_fd', 'gt_15_fd', 'gt_20_fd']
csv_filler_keys += ['cover_{}_{}'.format(hemi, lobe) for lobe in lobes
                    for hemi in ['lh', 'rh']]

csv_row = [fillers[k] for k in csv_filler_keys]

csv_header = ['Subject', 'Run.name', 'GM.SD', 'WM.SD', 'GM.WM.Rsqrd',
              'GM.WM.SNR', 'FDRMS.Mean', 'FDRMS.95th', 'FDRMS.thr.02',
              'FDRMS.thr.05', 'FDRMS.thr.10', 'FDRMS.thr.15', 'FDRMS.thr.20']
csv_header += ['Missing.{}.{}'.format(hemi, lobe) for lobe in lobes
               for hemi in ['lh', 'rh']]

csv = '\n'.join([','.join(csv_header), ','.join(map(str, csv_row))]) + '\n'
csv_f = open('{}/QA_stats.csv'.format(outdir), 'w')
csv_f.write(csv)
csv_f.close()
