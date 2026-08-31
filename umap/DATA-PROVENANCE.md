# Provenance and scope

## Observation source

The S-expression dataset contains accepted timestamp-level Jicamarca vertical
ion-drift observations from eleven public campaigns spanning 1984–1993. Source
records were retrieved from the Jicamarca Madrigal service. Valid `VIPN` and
`DVIPN` measurements between 300 and 500 km were combined by inverse-variance
weighting; at least five altitude samples were required per timestamp.

NASA OMNI daily data supplied F10.7 and Kp. Days with daily Kp above 3 were
excluded from the quiet-background calibration. The verified Common Lisp port
of the IRI-retained Scherliess–Fejer 1999 `VDRIFT` routine supplied the SF99
prediction at the observation local time, day of year, Jicamarca longitude, and
daily F10.7.

This bundle distributes the final processed records needed for the reported
calculation. It does not require collaborators to contact the original services
or reconstruct preprocessing choices before reproducing the numerical result.

## Validation

Complete campaigns form outer folds. Every transformation and transport model
uses the remaining campaigns only. The treatment is high solar flux
(`F10.7 >= 140`) versus low solar flux (`F10.7 <= 100`). The confounder space
contains local time, season, SF99 background, and measurement uncertainty. The
drift residual is excluded from matching because it is the effect target.

When the smaller treatment group contains less than 20% as many observations
as the larger group, the fold receives no transport correction and reverts to
SF99. This prevents forced mass matching under inadequate treatment support.

## Scope limitation

The dataset is historically calibrated Jicamarca material. It does not contain
the unavailable five-minute May 2025 numerical response series. It also does
not silently substitute ROCSAT satellite measurements for Jicamarca VIPN.
ROCSAT is reserved for independent multivariate and longitudinal validation.

## Method reference

Dong, M. et al. “Causal identification of single-cell experimental
perturbation effects with CINEMA-OT.” *Nature Methods* 20, 1769–1779 (2023).
DOI: <https://doi.org/10.1038/s41592-023-02040-5>.
