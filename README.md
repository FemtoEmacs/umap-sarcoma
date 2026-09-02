# Sarcoma evidence UMAP

This repository builds interactive UMAPs of sarcoma clinical-evidence records.
The published `index.html` contains 600 observations derived from survival
curves and can color the same map by sarcoma type, therapy, study, time window,
and survival measurements.

The scientific preparation, UMAP calculation, cluster discovery, and scoring
programs use dependency-free Common Lisp. The generated page uses pinned
browser modules for its interactive display.

## Requirements

- SBCL 2.x
- A current web browser
- Internet access while viewing generated HTML, because the page imports
  `umap-js` 1.3.3 and D3 7.9.0 from `esm.sh`

No Quicklisp, ASDF system, Python, Node.js, npm, or external numerical library
is required.

After cloning, change into the cloned repository directory. Run all commands
below from that repository root; its name and location do not matter.

## Build the main sarcoma UMAP

The generated evidence records are stored in the repository. Regenerate them
after changing the source evidence or preparation settings:

```sh
sbcl --script prepare-umap-data.lisp pilot-problem.sexp
```

The command reads the source, destination, window settings, and output schema
from `pilot-problem.sexp`. It writes the data file declared by `:data :file`,
which is `data/pilot-windows.sexp` for this problem. Build the interactive page
from the same manifest:

```sh
sbcl --script build-umap.lisp pilot-problem.sexp index.html
```

Open `index.html` in a browser. The browser calculates the UMAP with the
parameters and fixed seed declared in `pilot-problem.sexp`. The current
manifest uses 300 neighbors, a minimum distance of 0.72, 500 epochs, and seed
20260831.

To calculate the same scientific object in Common Lisp, discover clusters,
classify them by sarcoma type, and score the partition, run:

```sh
sbcl --script score-umap.lisp pilot-problem.sexp
```

This is a general manifest-driven command. It does not contain the pilot data
path, feature count, label field, or UMAP parameters. For this run,
`pilot-problem.sexp` declares `data/pilot-windows.sexp` under `:data`. Both
`build-umap.lisp` and `score-umap.lisp` resolve that path relative to the
manifest and use the same dataset reader and `:embedding` declaration.

The manifest's `:scoring` section declares the medical label, output file,
V-measure beta, and DBSCAN settings. The command constructs whatever feature
array the manifest describes, calculates the two-dimensional UMAP, discovers
and classifies clusters, and writes the coordinate array, assignments,
classifications, and scores to the declared output file.

Output names follow the manifest name. For example, `pilot-problem.sexp`
writes `output/pilot-problem-score.sexp`. When `:scoring` does not declare an
`:output`, the scorer automatically uses `output/MANIFEST-NAME-score.sexp`.

The implementation in `src/common-lisp-umap.lisp` uses exact nearest
neighbors, smooth k-nearest-neighbor distances, fuzzy-set union, and stochastic
layout optimization. The complete internal result also retains the neighbor
arrays, local distance parameters, and fuzzy graph. The saved result is kept
smaller because the coordinates and fixed parameters are sufficient to repeat
cluster discovery and scoring.

`src/embedding-clusters.lisp` applies DBSCAN to standardized UMAP coordinates.
Its default epsilon is selected from the knee of the 5-neighbor distance
curve. DBSCAN cluster number `-1` means noise. Classification does not alter
the discovered clusters: it reports each cluster's size, dominant medical
label, label counts, and purity.

The manifest also declares:

- the input file and embedding vector;
- required and unique fields;
- standardization;
- density-contour settings;
- color views;
- tooltip fields and Kaplan-Meier plots.

## Build the molecular-dimensions UMAP

The molecular experiment adds eight declared molecular-context indicators to
the survival-centered representation:

```sh
sbcl --script prepare-umap-data.lisp molecdim-problem.sexp
sbcl --script build-umap.lisp molecdim-problem.sexp molecdim.html
```

The molecular manifest declares its source evidence, molecular annotation
file, window settings, and generated data path. The first command writes
`data/molecdim-windows.sexp`. The second command builds `molecdim.html`.

## Build another manifest

The general command is:

```sh
sbcl --script build-umap.lisp PROBLEM-DIRECTORY-OR-FILE OUTPUT.html
```

A manifest file uses the `:umap-problem` format shown in
`pilot-problem.sexp`. Relative data paths are resolved from the manifest's
directory. The builder reads and validates the data, embeds it as JSON, and
writes the HTML. UMAP coordinates are then calculated in the browser.

## Score a labeled partition with V-measure

`src/v-measure.lisp` is self-contained ANSI Common Lisp. It uses no other
project source file and no external package. It calculates:

- the label-by-cluster contingency array;
- homogeneity;
- completeness;
- weighted V-measure.

The complete scorer consumes the same manifest and records as the HTML
builder:

| Program | Input |
| --- | --- |
| `build-umap.lisp` | Manifest plus evidence records; the browser calculates coordinates |
| `score-umap.lisp` | Manifest plus evidence records; Common Lisp calculates coordinates, clusters, classifications, and score |
| `v-measure.lisp` | `N x 2` coordinate array, `N` medical labels, and `N` cluster assignments |

V-measure compares known medical labels with cluster assignments. It does not
infer clusters from coordinates. `embedding-clusters.lisp` performs that
separate step so its algorithm and parameters remain visible.

Start SBCL and load the scorer:

```lisp
(load "src/v-measure.lisp")
```

Create one input object. Every row in the coordinate array must correspond to
the label and cluster value at the same position:

```lisp
(defparameter *umap-to-score*
  (make-umap-score-input
   #2A((0.0d0 0.0d0)
       (0.1d0 0.0d0)
       (2.0d0 2.0d0)
       (2.1d0 2.0d0))
   #(:soft-tissue :soft-tissue :gist :gist)
   #(0 0 1 1)))
```

Calculate the score:

```lisp
(defparameter *v-result* (score-umap-clusters *umap-to-score*))

(umap-v-measure-result-homogeneity *v-result*)
(umap-v-measure-result-completeness *v-result*)
(umap-v-measure-result-v-measure *v-result*)
(umap-v-measure-result-contingency *v-result*)
```

The default `beta` is 1.0, which balances homogeneity and completeness. A
larger value gives more weight to completeness and therefore gives a stronger
penalty when one medical label is fragmented across several clusters:

```lisp
(score-umap-clusters *umap-to-score* :beta 2.0d0)
```

The coordinate array is retained in the scoring input for the later cluster
classification stage. The present V-measure calculation uses the label and
cluster vectors after validating that all three inputs describe the same
number of observations.

## Tests

Run the V-measure tests alone:

```sh
sbcl --script vendor/test-cases/run-tests.lisp tests/v-measure-tests.lisp
```

Run the Common Lisp UMAP and clustering tests alone:

```sh
sbcl --script vendor/test-cases/run-tests.lisp tests/common-lisp-umap-tests.lisp
```

Run the complete dependency-free Common Lisp suite:

```sh
sbcl --script tests/run-all.lisp
```

Run the general UMAP-builder tests:

```sh
sbcl --script tests/general-umap-tests.lisp
```

The V-measure suite checks the published reference example, perfect
partitions, fragmentation, beta weighting, permutation invariance, symmetry,
contingency totals, invalid input, and score bounds.

## Main files

- `pilot-problem.sexp` — manifest for the published sarcoma evidence UMAP
- `data/pilot-landmarks.sexp` — source survival landmarks
- `prepare-umap-data.lisp` — prepares evidence data from any supported manifest
- `build-evidence-data.lisp` — compatibility name for manifest-driven preparation
- `data/pilot-windows.sexp` — generated main-map records
- `build-umap.lisp` — manifest-driven HTML builder
- `score-umap.lisp` — general manifest-driven UMAP, cluster, and score command
- `src/general-umap.template` — interactive browser template
- `index.html` — generated main sarcoma UMAP
- `molecdim-problem.sexp` — molecular-dimensions manifest
- `data/molecular-contexts.sexp` — declared molecular annotations and features
- `build-molecdim-data.lisp` — compatibility name for manifest-driven preparation
- `molecdim.html` — generated molecular-dimensions UMAP
- `src/v-measure.lisp` — dependency-free V-measure implementation
- `src/common-lisp-umap.lisp` — dependency-free UMAP implementation
- `src/embedding-clusters.lisp` — DBSCAN discovery and label classification
- `run-sarcoma-umap.lisp` — backward-compatible shortcut for the pilot manifest
- `tests/v-measure-tests.lisp` — V-measure behavioral and invariant tests
- `tests/common-lisp-umap-tests.lisp` — UMAP and clustering tests
- `vendor/test-cases/` — dependency-free Common Lisp test runner
- `paper/` — manuscript and supporting notes

## genAI disclosure

Codex genAI assisted with implementation, testing, documentation, and the
interactive display. The repository keeps scientific inputs, transformations,
parameters, and executable tests available for review.
