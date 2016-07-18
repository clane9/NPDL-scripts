import numpy as np
import npdl_utils as nu
import subprocess as sp
import gzip as gz
import os
import tempfile as tf

tmpdir = tf.mkdtemp(prefix='/tmp/make_sl-')
# output dir for searchlights
sl_dir = '{}/data/searchlight'.format(os.environ['NPDL_SCRIPT_DIR'])

# set radius range (in mm)
radii = np.arange(4, 21, 2)

# hard-coded number of vertices in 32k_fs_LR
num_verts = 32492

inds = np.arange(num_verts, dtype=int).reshape(-1, 1)
inds_f = '{}/all_inds.txt'.format(tmpdir)
np.savetxt(inds_f, inds, fmt='%d')

for hemi in 'lh', 'rh':
  surf = '{}/subjects/32k_fs_LR/surf/{}.midthickness.surf.gii'.format(os.environ['NPDL_SCRIPT_DIR'], hemi)
  for radius in radii:
    sl_f = '{}/sl_{}mm.{}.shape.gii'.format(tmpdir, radius, hemi)
    # make geodesic rois for this search space (all the searchlights)
    sp.call('wb_command -surface-geodesic-rois {} {} {} {}'.format(surf, radius, inds_f, sl_f), shell=True)
    # read back in the rois
    sl = nu.img_read(sl_f)
    max_row_len = int(np.max(np.sum(sl, 1)))
    sl_inds = [row.nonzero()[0].astype('S6').tolist() for row in sl]
    # pad with invalid values (-99)
    sl_inds = [row + ['-99'] * (max_row_len - len(row)) for row in sl_inds]
    # combine as string
    sl_inds = '\n'.join([','.join(row) for row in sl_inds])
    # writing as gzip instead of standard text file saves io time
    f = gz.open('{}/sl_{}mm_inds.{}.csv.gz'.format(sl_dir, radius, hemi), 'wb')
    f.write(sl_inds)
    f.close()
