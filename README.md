# ionospheric-vdrift

Reproducible Common Lisp implementation and evaluation material for the
Scherliess--Fejer 1999 (SF99) empirical model of quiet-time equatorial
F-region vertical plasma drift.

The repository also contains a general manifest-driven interactive UMAP
builder and an example based on historical Jicamarca observations. Open
`index.html` in a current browser to see the published map, change its
coloring, and inspect individual observations.

## Scope

SF99 estimates vertical plasma drift in metres per second from local time,
geographic longitude, day of year, and daily F10.7. It is a quiet-time
climatology. It does not calculate the complete state of the ionosphere or
explicit storm-time prompt-penetration and disturbance-dynamo responses.

## Requirements

- A current web browser for `index.html`.
- Internet access while viewing the map. The page imports pinned D3 7.9.0 and
  `umap-js` 1.3.3 browser modules from `esm.sh`.
- SBCL 2.x to run the scientific code, rebuild the map, and run the tests.

The repository uses no Quicklisp, ASDF system, Python package, package manager,
or external numerical library. The test framework, coefficients, processed
UMAP observations, and reference outputs are included.

## Evaluate SF99

Start SBCL from the repository root and load the model:

```lisp
(load "src/sf99-iri.lisp")
(defparameter *coefficients*
  (fejer-sf99-read-data "data/sf99-iri-coefficients.sexp"))
(fejer-sf99-drift-from-data *coefficients* 19.5 283.0 80.0 140.0)
```

The arguments after the coefficient data are local time in hours, east
longitude in degrees, day of year, and daily F10.7. The returned value is
vertical drift in metres per second.

## Rebuild the UMAP page

From the repository root:

```sh
sbcl --script build-umap.lisp examples/jicamarca-sexpr output/jicamarca.html
```

The builder accepts manifest directories for S-expression, CSV, multiscale
contour, and H5AD examples. Relative data paths are resolved from each
manifest. The H5AD adapter requires the `h5dump` executable on `PATH`; the
other examples need only SBCL. The generated pages use a fixed browser-side
pseudorandom seed for UMAP.

To rebuild the leave-campaign-out CINEMA-OT annotations used by the Jicamarca
UMAP:

```sh
sbcl --script build-causal-effects.lisp
```

Its Common Lisp implementation and processed observations are contained in
this repository.

## Test

From the repository root:

```sh
sbcl --script tests/run-all.lisp
sbcl --script tests/general-umap-tests.lisp
```

The suite checks the Common Lisp sources, verifies all 624 coefficients, and
compares the port against 450 outputs from the compiled official IRI-2020
`VDRIFT` routine with a tolerance of 0.000005 m/s. It also rebuilds and checks
the interactive UMAP.

## Repository layout

- `index.html` -- published interactive UMAP for GitHub Pages
- `build-umap.lisp` -- general manifest-driven UMAP builder
- `build-causal-effects.lisp` -- leave-campaign-out causal annotations
- `examples/` -- executable S-expression, CSV, contour, and H5AD examples
- `output/` -- generated example pages
- `src/` -- dependency-free SF99 implementation and figure calculation
- `data/` -- SF99 reference material and processed UMAP inputs
- `tests/` -- one-command scientific and reproducibility tests
- `tools/` -- repository-contained data conversion utility
- `umap/` -- UMAP builder, processed observations, template, and provenance
- `vendor/test-cases/` -- dependency-free Common Lisp test runner

## Scientific provenance

SF99 was published as:

L. Scherliess and B. G. Fejer, "Radar and satellite global equatorial F region
vertical drift model," *Journal of Geophysical Research: Space Physics*, 104,
6829--6842 (1999). DOI: <https://doi.org/10.1029/1999JA900025>.

The implementation is a direct Common Lisp port of the SF99 `VDRIFT` routine
retained in the official IRI-2020 distribution. See the metadata in the
coefficient and oracle S-expressions and `umap/DATA-PROVENANCE.md` for source
hashes, processing history, and limitations.

## genAI disclosure

Codex genAI helped organize the reproducibility bundle and documentation.
Scientific claims and numerical behavior are checked against cited primary
sources and executable reference tests.
