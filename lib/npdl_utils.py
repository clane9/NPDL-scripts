#!/usr/bin/env python

"""Utility functions and classes for NPDL python scripts.
"""

# So you can print to stderr/stdout
from __future__ import print_function

import gdist
import nibabel as nib
from nibabel import gifti
import numpy as np
import os
import re
from shutil import copy, rmtree
import subprocess as subp
import sys
import tempfile as tf

# set Agg backend so that making figures doesn't depend on an X11 server
# http://matplotlib.org/faq/howto_faq.html#matplotlib-in-a-web-application-server
import matplotlib as mpl
mpl.use('Agg')
from matplotlib import pyplot as plt

class Logger(object):
  """For logging, warnings, errors."""

  def __init__(self, global_log=None, local_log=None, pid=None):
    self.set_pid(pid)
    self.set_global_log(global_log)
    self.set_local_log(local_log)
    return

  def set_pid(self, pid):
    self.pid = pid
    if pid is not None:
      self.pid_s = '(pid={}) '.format(pid)
    else:
      self.pid_s = ''
    return

  def set_global_log(self, global_log):
    self.global_log = global_log
    return

  def set_local_log(self, local_log):
    self.local_log = local_log
    return

  def error(self, msg):
    msg = 'ERROR: {}'.format(msg)
    self._print(msg, f=sys.stderr)
    return

  def warning(self, msg):
    msg = 'WARNING: {}'.format(msg)
    self._print(msg, f=sys.stderr)
    return

  def log(self, msg):
    self._print(msg, f=sys.stdout)
    return

  def _print(self, msg, f=None):
    for f in [self.global_log, self.local_log, f]:
      if f is not None:
        print(msg, file=f)
    return

class NPDLError(Exception):
  """Lab-specific exceptions."""

  def __init__(self, msg):
    super(NPDLError, self).__init__(msg)
    return

class Surface(object):
  """Class for representing cortical surfaces

  Attributes:
    surf_path (str): Surface file path.
    coords (2D array): X, Y, Z coordinates for each surface vertex.
    faces (2D array): Vertex index triplets for each triangular face in surface
      mesh.
    num_verts (int): Number of vertices in surface.
    neighbors (2D array): Adjacency list represented as padded 2D array. The
      ith row contain neighbors for vertex i. Pad value is num_verts.
  """

  def __init__(self, surf_path, max_neighbors=50):
    self.surf_path = surf_path
    try:
      surf = gifti.read(surf_path)
    except:
      raise NPDLError(('Surface: {} does not exist ' +
                       'or is not a valid Gifti file.').format(surf))

    self.coords, self.faces = [surf.darrays[i].data for i in 0, 1]
    self.coords = self.coords.astype(np.float64)
    self.faces = self.faces.astype(np.int32)

    self.num_verts = self.coords.shape[0]
    self.neighbors = self.construct_neighbors(max_neighbors)
    return

  def distance(self, src, trg=None, max_distance=None):
    """Compute minimum geodesic distance between source vertices and target
    vertices using gdist library.
    """
    src = np.array(src, dtype=np.int32)
    if trg is not None:
      trg = np.array(trg, dtype=np.int32)
    if max_distance is not None:
      max_distance = np.float64(max_distance)
      distances = gdist.compute_gdist(self.coords, self.faces, src, trg, max_distance)
    else:
      distances = gdist.compute_gdist(self.coords, self.faces, src, trg)
    return distances

  def construct_neighbors(self, max_neighbors):
    """Reshape list of triangle faces into padded adjacency list (2D Array)."""
    nbr_dict = dict()

    for face in self.faces:
      for i in [0, 1, 2]:
        other_inds = list({0, 1, 2} - {i})
        nbd = nbr_dict.get(face[i], [])
        for j in other_inds:
          nbd.append(face[j])
        nbr_dict[face[i]] = nbd

    neighbors = np.ones((self.num_verts, max_neighbors), dtype=int) * self.num_verts

    actual_max_neighbors = 0
    for v in xrange(self.num_verts):
      nbd = np.unique(nbr_dict[v])
      actual_max_neighbors = max(nbd.size, actual_max_neighbors)
      neighbors[v, :nbd.size] = nbd

    neighbors = neighbors[:, :actual_max_neighbors]
    return neighbors

  def find_neighbors(self, verts, lower=False, stat=None):
    """Find all (optionally lower) neighbors of a set of vertices."""
    neighbors = self.neighbors[verts, :]
    if lower and stat is not None:
      stat = np.hstack([stat.reshape(-1), [np.nan]])
      lower_mask = stat[neighbors] <= stat[verts].reshape((-1, 1))
      neighbors = neighbors[lower_mask]
    neighbors = np.setdiff1d(np.unique(neighbors), [self.num_verts])
    return neighbors

  def project_coord(self, coord):
    """Project a coordinate onto the surface."""
    coord = np.array(coord).reshape(1, 3)
    sqrd_dists = np.sum((self.coords - coord)**2, axis=1)
    vertex = np.argmin(sqrd_dists)
    return vertex

def img_read(img_path):
  """Read a .nii, .nii.gz, or .gii image.

  Args:
    img_path (str): Path to image file.

  Returns:
    img (2D array): First dimension is time, second dimension contains all
      spatial dimensions flattened according to numpy.reshape function.
  """
  img_path, img_type = check_img_path(img_path)
  if img_type == 'nii':
    img = load_nii(img_path, compressed=False)
  elif img_type == 'nii.gz':
    img = load_nii(img_path, compressed=True)
  else:
    img = load_gii(img_path)
  return img

def check_img_path(img_path, exists=True):
  """Check image file extention."""
  img_path = img_path.strip()
  if exists and not os.path.isfile(img_path):
    raise NPDLError('Image file ({}) does not exist.'.format(img_path))
  ext_patt = r'(\.nii(\.gz)?|\.gii)$'
  img_ext = re.search(ext_patt, img_path)
  if img_ext is None:
    raise NPDLError(('Image file ({}) does not match any accepted' +
                     'extensions (.nii, .nii.gz, .gii)').format(img_path))
  img_type = img_ext.group()[1:]
  return img_path, img_type

def load_nii(img_path, compressed=False):
  """Load Nifti or compressed Nifti."""
  tmpdir = None
  if compressed and not gz_test(img_path):
    # Apparently some files (including our raw data) have a .gz extension but
    # are not gzipped, resulting in error. Remove extension before giving up.
    tmpdir = tf.mkdtemp(prefix='img_read-')
    img_copy = '{}/img.nii'.format(tmpdir)
    copy(img_path, img_copy)
    img_path = img_copy
  try:
    img = nib.load(img_path).get_data()
  except:
    raise NPDLError('Image file ({}) could not be loaded'.format(img))
  # Reshape 4d nifti array to 2d, with time as first axis.
  newshape = (-1, np.product(img.shape[:3]))
  img = img.reshape(newshape)
  if tmpdir is not None:
    rmtree(tmpdir)
  return img

def gz_test(path):
  """Test if file is gzipped using magic number.

  References:
    http://stackoverflow.com/questions/13044562/python-mechanism-to-identify-compressed-file-type-and-uncompress
    http://stackoverflow.com/questions/3703276/how-to-tell-if-a-file-is-gzip-compressed
  """
  magic = "\x1f\x8b\x08"
  f = open(path)
  if f.read(len(magic)) == magic:
    return True
  else:
    return False

def load_gii(img_path):
  """Load Gifti."""
  try:
    img = gifti.read(img_path)
  except:
    raise NPDLError('Image file ({}) could not be loaded'.format(img))
  img = np.array(map(lambda d: d.data, img.darrays))
  return img

def img_save(img_path, img, surf_path=None):
  img_path, img_type = check_img_path(img_path, exists=False)
  if img_type in {'.nii', '.nii.gz'}:
    save_nii(img_path, img)
  else:
    if surf_path is None:
      raise NPDLError('A path to a valid surface is required to save a Gifti file.')
    save_gii(img_path, img, surf_path)
  return

def save_nii(img_path, img):
  if len(img.shape) == 1:
    img = img.reshape((1, -1))
  img = img.T
  img = img.reshape((img.shape[0], 1, 1, img.shape[1]))
  img = nib.Nifti1Image(img, np.eye(4))
  nib.save(img, img_path)
  return

def save_gii(img_path, img, surf_path):
  tmpdir = tf.mkdtemp(prefix='img_save-')
  tmp_img_path = '{}/img.nii.gz'.format(tmpdir)
  save_nii(tmp_img_path, img)
  status = subp.call(('wb_command -metric-convert -from-nifti ' +
                      '{} {} {}').format(tmp_img_path, surf_path, img_path), shell=True)
  if status != 0:
    raise NPDLError('Failed to save Gifti file: {}.'.format(img_path))
  return

def read_table(f, skip_head=False, comment="#", row_patt=r'[\r\n]+',
               col_patt=r'[ ,\t]+', num_conv=True):
  """Read tabular data, possibly of different formats.
  """
  f = f.strip()
  try:
    table = open(f).read().strip()
  except IOError:
    raise NPDLError('File ({}) does not exist.'.format(f))
  table = [row for row in re.split(row_patt, table)
           if not (len(row) == 0 or row[0] == comment)]
  if skip_head:
    table = table[1:]
  table = [re.split(col_patt, row.strip()) for row in table]
  if num_conv:
    table = [map(num_convert, row) for row in table]
  return table

def num_convert(x):
  """Convert to number if possible.
  """
  try:
    return float(x)
  except:
    return x

def init_table(header, num_rows, default_val=np.nan):
  """Initialize a data table."""
  table = np.ndarray((num_rows+1, len(header)), dtype=object)
  table[:, :] = default_val
  table[0, :] = header
  return table

def normalize(X):
  """Subtract mean and divide by standard deviation."""
  return (X - X.mean())/X.std()

def resample(time_series, curr_bin_size, new_bin_size):
  """Resample a time-series to a different temporal resolution.

  Nearest-neighbor interpolation is used.

  Args:
    time_series (1D array): Float time-series.
    curr_bin_size (float): Current temporal resolution of time-series.
    new_bin_size (float): New temporal resolution of time-series (same units as
      ``curr_bin_size``).

  Returns:
    resampled (1D array): Resampled time-series.
  """
  if curr_bin_size == new_bin_size:
    resampled = time_series
  else:
    time_series = np.array(time_series)
    duration = time_series.size * curr_bin_size
    sample_locations = np.arange(new_bin_size/2., duration, new_bin_size)
    sample_inds = np.floor(sample_locations/curr_bin_size).astype(int)
    resampled = time_series[sample_inds]
  return resampled

def plot_hrf(psc, conds, out, ylim=None, stim_on_off=None, peak_on_off=None,
             tr=2.0, xunit=2.0, figw=6.0, figh=4.0):
  """
  Plot hrf time course for a set of conditions and save.

  Args:
    psc (dict): Dictionary mapping conditions to PSC time courses.
    conds (list): List of conditions to plot.
    out (str): Path to output figure.
    ylim (tuple): 2-tuple y-axis limits.
    stim_on_off (tuple): 2-tuple containing start and stop of stimulus.
    peak_on_off (tuple): 2-tuple containing start and stop of peak window.
    tr (float): Duration of tr, which will determine placement of xticks.
    xunint (float): Unit of x axis (e.g. 2.0, 0.05).
    figw (float): Width of figure.
    figh (float): height of figure.
  """
  f, ax = prep_fig(0.7, 0.25, 0.1, 0.2, figw, figh)

  yres = 0.2
  if ylim is None:
    ymin = np.floor(np.min([np.min(psc[cond]) for cond in conds])/yres)*yres
    ymax = np.ceil(np.max([np.max(psc[cond]) for cond in conds])/yres)*yres
    ymin = np.min([-yres, ymin])
    ymax = np.max([yres, ymax])
    ax.set_ylim(ymin, ymax)
  else:
    ymin, ymax = ylim
    ax.set_ylim(*ylim)

  yticks = np.arange(ymin, ymax+.1, .2)
  yticklabels = map(lambda y: '{0:0.1f}'.format(y), yticks)
  plt.yticks(yticks, yticklabels)

  xmin = 0
  xmax = np.max([psc[cond].size for cond in conds])*xunit
  ax.set_xlim(xmin, xmax)

  xvals = np.arange(xunit/2., xmax, xunit)
  xticks = np.arange(tr, (np.floor(xmax/tr)+1)*tr, tr)
  xticklabels = map(lambda x: '{0:0.1f}'.format(x), xticks)
  plt.xticks(xticks, xticklabels)

  plt.xlabel('Seconds')
  plt.ylabel('Percent Signal Change')

  if stim_on_off is not None:
    ax.bar([stim_on_off[0]], [ymax], stim_on_off[1] - stim_on_off[0],
            color=(0.8, 0.8, 0.8, 0.5), edgecolor='none', label='stim')
  if peak_on_off is not None:
    ax.bar([peak_on_off[0]], [ymax], peak_on_off[1] - peak_on_off[0],
            color=(0.3, 0.3, 0.3, 0.5), edgecolor='none', label='peak')

  # Don't show markers if the plot is high-res.
  if xvals.size > 50:
    ms = 0.
  else:
    ms = 7.
  for cond in conds:
    ax.plot(xvals[:psc[cond].size], psc[cond], marker='o', ms=ms,
            ls='-', lw=3., label=cond, clip_on=False)

  ax.legend(loc='upper right', bbox_to_anchor=(1.05, 1.05), borderpad=0.2,
            labelspacing=0.2)

  plt.savefig(out, dpi=400, transparent=True)
  return

def prep_fig(leadbuff, backbuff, bottombuff, topbuff, figw, figh):
  """Prepare single axis figure in standard way."""
  plotw = figw - (leadbuff + backbuff)

  ploth = figh - (bottombuff + topbuff)

  f, ax = plt.subplots(1, 1, figsize=(figw, figh))

  pos = (leadbuff/figw, bottombuff/figh, plotw/figw, ploth/figh)
  ax.set_position(pos)
  ax.spines['right'].set_color('none')
  ax.spines['top'].set_color('none')
  ax.spines['bottom'].set_position(('data', 0))

  #only left and bottom ticks
  ax.yaxis.set_ticks_position('left')
  ax.xaxis.set_ticks_position('bottom')
  return f, ax

def fit_glm(TS, DM, cfd_mat=None, intercept=True, outdir=None,
            out_prefix=None, logger=None):
  """Calculate GLM beta weights. Return baseline and PSC betas.
  """
  # prepend intercept
  if intercept:
    DM = np.hstack([np.ones((DM.shape[0], 1)), DM])
  # append confound regressors
  if not (cfd_mat is None or cfd_mat.shape[1] == 0):
    DM = np.hstack([DM, cfd_mat])
  # save design matrix
  if outdir is not None and out_prefix is not None:
    np.savetxt('{}/{}_design.txt'.format(outdir, out_prefix), DM, delimiter=' ')
  # calculate singular values
  try:
    S = np.linalg.svd(DM, compute_uv=False)
  except LinAlgError:
    raise NPDLError('Bad design matrix: SVD did not converge.')
  S_str = ' '.join(['{0:.0f}'.format(s) for s in S])
  if logger is not None and out_prefix is not None:
    logger.log('Singular values for {} design mat: {}.'.format(out_prefix, S_str))
  # determine if rank deficient as in matrix_rank function
  eps = np.finfo('f8').eps
  thresh = S.max() * np.max(DM.shape) * eps
  rank = np.sum(S > thresh)
  if logger is not None and out_prefix is not None:
    logger.log('Design matrix width for {}: {}; rank: {}.'.format(out_prefix, DM.shape[1], rank))
  if rank < S.size:
    raise NPDLError('Design matrix is rank deficient.')
  # calculate betas
  # y = X*beta
  # beta = (X'X)^-1 * X' * y
  TS = TS.reshape((-1, 1))
  beta = np.dot(np.linalg.inv(np.dot(DM.T, DM)), np.dot(DM.T, TS))
  if outdir is not None and out_prefix is not None:
    np.savetxt('{}/{}_beta.txt'.format(outdir, out_prefix), beta)
  beta = beta.reshape(-1)
  if intercept:
    bl, beta = beta[0], beta[1:]
  else:
    bl = None
  return bl, beta

def block_diag(*arrs):
  """
  Create a block diagonal matrix from provided arrays.

  Given the inputs `A`, `B` and `C`, the output will have these
  arrays arranged on the diagonal::

  [[A, 0, 0],
  [0, B, 0],
  [0, 0, C]]

  NOTE: This function is needed in place of scipy.linalg.block_diag in
  roi_extract because, in Scipy v. 0.17.0, the ability to create a
  block-diagonal matrix from 0-width matrices was lost.
  """
  
  # Initialize block diag matrix with (0, 0) shape.
  block = np.zeros((0, 0))
  
  # Make sure arrs contains actual numpy arrays
  arrs = [np.array(arr) for arr in arrs]
  
  for arr in arrs:
    # 1-D vectors should be treated as row-vector, for consistency with scipy
    # block_diag function.
    if len(arr.shape) == 1:
      arr = arr.reshape(1, -1)
    
    # Pad block with zeros below, and arr with zeros above.
    num_new_rows = arr.shape[0]
    num_current_rows = block.shape[0]
    block = np.vstack([block, np.zeros((num_new_rows, block.shape[1]))])
    arr = np.vstack([np.zeros((num_current_rows, arr.shape[1])), arr])

    # Stack block and arr horizontally
    block = np.hstack([block, arr])

  return block

def convert_coords(coord, inspace='MNI305', outspace='MNI152'):
  """Convert MRI coordinates between template spaces.

  Args:
    coord: (X, Y, Z) coordinate as a Numpy array or list.
    inspace: Input coordinate space (one of 'MNI305', 'MNI152', 'Tal').
    outspace: Output coordinate space.
  """
  # Define base transformation matrices.
  mats = {
      # Refs:
      # - https://mail.nmr.mgh.harvard.edu/pipermail//freesurfer/2013-November/034417.html
      # - https://surfer.nmr.mgh.harvard.edu/fswiki/CoordinateSystems
      ('MNI305', 'MNI152'): np.array([[0.9975, -0.0073, 0.0176, -0.0429],
                                      [0.0146, 1.0009, -0.0024, 1.5496],
                                      [-0.0130, -0.0093, 0.9971, 1.1840],
                                      [0.0000, 0.0000,  0.0000,  1.0000]]),
      
      # Refs:
      # - http://www.brainmap.org/icbm2tal/
      ('MNI152', 'Tal'): np.array([[0.9464, 0.0034, -0.0026, -1.0680],
                                   [-0.0083, 0.9479, -0.0580, -1.0239],
                                   [0.0053, 0.0617,  0.9010, 3.1883],
                                   [0.0000, 0.0000,  0.0000,  1.0000]])
      }

  # Invert tranformations.
  mats[('MNI152', 'MNI305')] = np.linalg.inv(mats[('MNI305', 'MNI152')])
  mats[('Tal', 'MNI152')] = np.linalg.inv(mats[('MNI152', 'Tal')])

  # Concatenate transformations.
  mats[('MNI305', 'Tal')] = mats[('MNI152', 'Tal')].dot(mats[('MNI305', 'MNI152')])
  mats[('Tal', 'MNI305')] = mats[('MNI152', 'MNI305')].dot(mats[('Tal', 'MNI152')])

  # Convert coordinate to numpy column vector, and add a 1.
  coord = np.vstack([np.array(coord).reshape(3, 1), [[1.]]])
  
  # Transform coordinate.
  new_coord = mats[(inspace, outspace)].dot(coord)

  # Re-format coordinate.
  new_coord = new_coord.reshape(-1)[:3]
  return new_coord
