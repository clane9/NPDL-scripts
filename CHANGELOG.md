# Change Log

Important changes to the lab scripts will be documented here. Please see 
[this guide](http://keepachangelog.com/en/0.3.0/) for keeping this document
neat.

## [Unreleased]

### Changed
- Changed takesnap inf view angle to fix shadow from @judyseinkim.
- Changed scripts to record version number from @clane9.
- Changed method for computing beta values in roi_extract. Previously, betas were
  computed the naive way, by explicitly inverting `X' * X`. Although correct,
  this is slow and numerically unstable. It's better to use the SVD, as
  discussed [on wikipedia](https://en.wikipedia.org/wiki/Linear_least_squares_(mathematics)#Orthogonal_decomposition_methods)
  (from @clane9).

### Fixed
- Redundant spike covariates are now removed before fitting the GLM. This
  prevents the "Design matrix is rank-deficient" error from coming up in this
  case (from @clane9).

## [1.0] - 2016-08-09

- First tracked release from @clane9.
