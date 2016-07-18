"""
NPDL Tools for MVPA analyses.
"""
import numpy as np

# the warnings are **very** annoying!
import warnings
with warnings.catch_warnings():
  warnings.simplefilter("ignore")
  from mvpa2.base.dochelpers import _repr_attrs
  from mvpa2.misc.neighborhood import QueryEngineInterface

import os
import gzip as gz

import ipdb

class CachedSurfaceQueryEngine(QueryEngineInterface):
  '''
  Modified surface-based query engine for running pyMVPA searchlight analyses.
  Based on built-in SurfaceQueryEngine class defined here::

    https://github.com/PyMVPA/PyMVPA/blob/master/mvpa2/misc/surfing/queryengine.py

  Cached searchlight ROIs for a fixed range of radii exist for the 32k_fs_LR
  midthickness lh/rh surfaces. This query engine class provides an interface
  for pyMVPA to these searchlights. The cached searchlight ROIs **will not** be
  perfect geodesic ROIs for your subjects, since they are not based on
  subject-specific anatomy. I think the speed benefit is worth it though.

  The key method is ``query_byid``, which maps a node index on the surface to a
  list of dataset feature inds within the node's searchlight ROI.
  '''

  def __init__(self, hemi, radius, fa_node_key='node_indices'):
    '''Make a new CachedSurfaceQueryEngine
    Parameters
    ----------
    hemi: str
      'lh' or 'rh'.
    radius: float
      size of neighborhood.
    fa_node_key: str
      Key for feature attribute that contains node indices
      (default: 'node_indices').
    Notes
    -----
    After training this instance on a dataset and calling it with
    self.query_byid(vertex_id) as argument,
    '''
    self.hemi = hemi
    self.radius = radius
    self.fa_node_key = fa_node_key
    self._vertex2feature_map = None
    
    if hemi not in ['lh', 'rh']:
      raise ValueError('hemi must be either "lh" or "rh".')
    if radius not in range(8, 22, 2):
      raise ValueError('Radius must be one of [8, 10, 12, 14, 16, 18, 20].')
    radius = int(radius)
    
    # hard-coded verts of 32k_fs_LR
    self.nverts = 32492
    
    # Read in cached searchlight rois.
    self.sl = '{}/data/searchlight/sl_{}mm_inds.{}.csv.gz'.format(os.environ['NPDL_SCRIPT_DIR'], radius, hemi)
    self.sl = gz.open(self.sl, 'rb').read()
    # Collapse to 1-d because fromstring only reads a 1-d array.
    self.sl = self.sl.replace('\n', ',')
    self.sl = np.fromstring(self.sl, dtype='int32', sep=',')
    self.sl = self.sl.reshape((self.nverts, -1))
    # sl is a ragged 2d array, the ith row containing the searchlight vertices
    # for vertex i. The array is padded with an invalid value (-99) to make it
    # rectangular.
    self.invalid = -99
    return

  def __repr__(self, prefixes=None):
    if prefixes is None:
      prefixes = []
    return super(SurfaceQueryEngine, self).__repr__(
           prefixes=prefixes
           + _repr_attrs(self, ['hemi'])
           + _repr_attrs(self, ['radius'])
           + _repr_attrs(self, ['fa_node_key'],
                   default='node_indices'))

  def __reduce__(self):
    return (self.__class__, (self.hemi,
                 self.radius,
                 self.fa_node_key),
                 dict(_vertex2feature_map=self._vertex2feature_map))

  def __str__(self):
    return '%s(radius=%s, fa_node_key=%s)' % \
                         (self.__class__.__name__,
                          self.hemi,
                          self.radius,
                          self.fa_node_key)

  def _check_trained(self):
    if self._vertex2feature_map is None:
      raise ValueError('Not trained on dataset: %s' % self)

  @property
  def ids(self):
    self._check_trained()
    return self._vertex2feature_map.keys()

  def untrain(self):
    self._vertex2feature_map = None

  def train(self, ds):
    '''
    Train the queryengine
    Parameters
    ----------
    ds: Dataset
      dataset with surface data. It should have a field
      .fa.node_indices that indicates the node index of each
      feature.
    '''

    fa_key = self.fa_node_key
    nvertices = self.nverts
    nfeatures = ds.nfeatures

    if not fa_key in ds.fa.keys():
      raise ValueError('Attribute .fa.%s not found.', fa_key)

    vertex_ids = ds.fa[fa_key].value.ravel()

    # check that vertex_ids are not outside 0..nfeatures
    delta = np.setdiff1d(vertex_ids, np.arange(nvertices))

    if len(delta):
      raise ValueError("Vertex id '%s' found that is not in "
               "np.arange(%d)" % (delta[0], nvertices))
    
    # Each feature is associated with a unique vertex, so just use dict.
    self._vertex2feature_map = dict(zip(vertex_ids, xrange(vertex_ids.size)))
    return

  def query(self, **kwargs):
    raise NotImplementedError

  def query_byid(self, vertex_id):
    '''
    Return feature ids of features near a vertex
    Parameters
    ----------
    vertex_id: int
      Index of vertex (i.e. node) on the surface
    Returns
    -------
    feature_ids: list of int
      Indices of features in the neighborhood of the vertex indexed
      by 'vertex_id'
    '''
    self._check_trained()

    if vertex_id < 0 or vertex_id >= self.nverts or \
            round(vertex_id) != vertex_id:
      raise KeyError('vertex_id should be integer in range(%d)' % self.nverts)
    
    # query searchlight
    nearby_nodes = self.sl[vertex_id, :]
    # remove invalid values
    nearby_nodes = nearby_nodes[nearby_nodes != self.invalid]

    v2f = self._vertex2feature_map
    nearby_features = [v2f[node] for node in nearby_nodes]
    return nearby_features

if __name__ == '__main__':
  ipdb.set_trace()
  qe = CachedSurfaceQueryEngine('lh', 12)
