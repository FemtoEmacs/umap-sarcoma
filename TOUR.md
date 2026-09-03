# Sarcoma UMAP testing tour

This tour starts with the published sarcoma evidence UMAP and finishes with
the `smc-trainer` Transformer insertion demonstration. Run every shell block
from the `umap-sarcoma` root.

## Run this tour inside Emacs

Evaluate this block once, or add the `load-file` form to your Emacs
initialization:

```elisp
(load-file "/Users/eduardo/umap-sarcoma/stock-tour.el")
(stock-tour-open)
```

The shared runner places this `TOUR.md` in the upper window and a dedicated
Eshell below it. Put point inside any fenced `sh` block and type `C-c e` to
execute the entire block. Prose and `elisp` blocks are never executed.

The requirements are SBCL 2.x and a current browser. Data preparation, UMAP
scoring, clustering, AWRS-SMC, and Transformer training use dependency-free
Common Lisp. No Quicklisp, Python, Node.js, or Conda environment is required.
The general UMAP pages need Internet access for their pinned browser modules;
the final Transformer demonstration works offline.

## 1. Build the published sarcoma evidence UMAP

```sh
sbcl --script prepare-umap-data.lisp pilot-problem.sexp
sbcl --script build-umap.lisp pilot-problem.sexp index.html
sbcl --script score-umap.lisp pilot-problem.sexp
open index.html
```

Expected browser check: the page contains 600 survival-window observations.
Change color views among sarcoma type, therapy, study, time window, and
survival measurements. Hovering a point should show study metadata and its
miniature time-to-event curve. The Common Lisp score is written to
`output/pilot-problem-score.sexp`.

## 2. Test the shared UMAP machinery and medical preparation

```sh
sbcl --script tests/run-all.lisp
sbcl --script tests/general-umap-tests.lisp
```

The suites cover evidence preparation, UMAP invariants, DBSCAN clustering,
V-measure, manifest parsing, validation, and HTML generation.

Individual suites can also be run through the vendored test runner:

```sh
sbcl --script vendor/test-cases/run-tests.lisp \
  tests/v-measure-tests.lisp
sbcl --script vendor/test-cases/run-tests.lisp \
  tests/common-lisp-umap-tests.lisp
```

## 3. Build the molecular-dimensions map

This experiment adds eight declared molecular-context indicators without
changing the general UMAP builder.

```sh
sbcl --script prepare-umap-data.lisp molecdim-problem.sexp
sbcl --script build-umap.lisp molecdim-problem.sexp molecdim.html
sbcl --script score-umap.lisp molecdim-problem.sexp
open molecdim.html
```

Expected artifacts are `data/molecdim-windows.sexp`, `molecdim.html`, and
`output/molecdim-problem-score.sexp`.

## 4. Exercise the declared representation experiments

Each builder writes the data named by its corresponding manifest. Each HTML
gets a distinct filename, so no experiment replaces the published map.

```sh
sbcl --script experiments/build-temporal-10.lisp
sbcl --script build-umap.lisp \
  experiments/temporal-10-problem.sexp \
  output/experiments/temporal-10.html

sbcl --script experiments/build-temporal-20.lisp
sbcl --script build-umap.lisp \
  experiments/temporal-20-problem.sexp \
  output/experiments/temporal-20.html

sbcl --script experiments/build-multiscale-10.lisp
sbcl --script build-umap.lisp \
  experiments/multiscale-10-problem.sexp \
  output/experiments/multiscale-10.html

sbcl --script experiments/build-typed-transforms.lisp
sbcl --script build-umap.lisp \
  experiments/typed-transforms-problem.sexp \
  output/experiments/typed-transforms.html

sbcl --script experiments/build-survival-progress.lisp
sbcl --script build-umap.lisp \
  experiments/survival-progress-problem.sexp \
  output/experiments/survival-progress.html

sbcl --script experiments/build-survival-progress-raw.lisp
sbcl --script build-umap.lisp \
  experiments/survival-progress-raw-problem.sexp \
  output/experiments/survival-progress-raw.html

sbcl --script experiments/build-cloglog-multiscale.lisp
sbcl --script build-umap.lisp \
  experiments/cloglog-multiscale-problem.sexp \
  output/experiments/cloglog-multiscale.html
```

Open any result for visual inspection, for example:

```sh
open output/experiments/survival-progress.html
```

## 5. Run the baseline SMC feature search

This is the earlier Lew-style SMC search. It can take substantially longer
than building an HTML page.

```sh
sbcl --script smc/search-umap.lisp smc/pilot-search.sexp
sbcl --script smc/build-best-html.lisp \
  smc/pilot-search-result.sexp \
  smc/pilot-search-best.html
open smc/pilot-search-best.html
```

The result S-expression preserves the search settings, history, particles,
and winning feature recipe. The HTML builder also preserves the selected data
and manifest beside the page.

```sh
sbcl --script vendor/test-cases/run-tests.lisp smc/tests.lisp
sbcl --script vendor/test-cases/run-tests.lisp smc/integration-tests.lisp
```

## 6. Run the AWRS-SMC feature search

```sh
sbcl --script awrs-smc/search-umap.lisp \
  smc/pilot-search.sexp \
  awrs-smc/pilot-search-awrs-result.sexp
sbcl --script smc/build-best-html.lisp \
  awrs-smc/pilot-search-awrs-result.sexp \
  awrs-smc/pilot-search-awrs-best.html
open awrs-smc/pilot-search-awrs-best.html
```

Expected check: `pilot-search-awrs-result.sexp` contains particle weights,
iterations, interactions, ESS, resampling, conditional draws, constraint
checks, rejections, terminal evaluations, and normalizer telemetry. The HTML
can display the winning Common Lisp coordinates or ask `umap-js` to recompute
the selected representation.

```sh
sbcl --script vendor/test-cases/run-tests.lisp awrs-smc/tests.lisp
```

## 7. Build and validate the sharded `smc-trainer` corpus

The corpus freezes the winning AWRS-SMC inputs and coordinates as numeric
supervision. The split is grouped by study.

```sh
sbcl --script smc-trainer/build-sharded-corpus.lisp \
  awrs-smc/pilot-search-awrs-result.sexp \
  smc-trainer/corpus/pilot-shards \
  25
sbcl --script smc-trainer/validate-corpus.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp
```

Expected corpus: 90 observations divided into physical shards, with 70
training and 20 validation records.

Test corpus construction, the full-gradient Transformer, serialization,
streaming, and deterministic training:

```sh
sbcl --script vendor/test-cases/run-tests.lisp smc-trainer/tests.lisp
sbcl --script vendor/test-cases/run-tests.lisp smc-trainer/trainer-tests.lisp
sbcl --script vendor/test-cases/run-tests.lisp smc-trainer/shard-tests.lisp
```

## 8. Train the Transformer and predict one profile

The Transformer trains a parametric functor from the six-dimensional selected
evidence representation to the fixed two-dimensional atlas. It learns where
to carry a new evidence profile without recomputing the atlas. This is an
operational learning-theory use of “functor”; no formal category-theoretic
identity or composition laws are claimed.

The implementation in `smc-trainer/transformer.lisp` uses native Common Lisp
arrays for learned matrices and intermediate tensors. Explicit dot products
and matrix-vector loops replace BLAS/LAPACK; nested lists remain only as the
portable version-1 S-expression serialization format.

```sh
sbcl --script smc-trainer/train.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp \
  smc-trainer/weights/pilot-coordinate-sharded.sexp \
  100 \
  0.002d0
sbcl --script smc-trainer/predict.lisp \
  smc-trainer/weights/pilot-coordinate-sharded.sexp \
  '(0.8 0.1 0.2 2.0 1.0 0.3)'
```

The predictor prints two coordinates in the frozen AWRS-SMC atlas. The six
numbers are raw feature values in the model artifact's declared schema order;
the predictor applies the stored training preprocessing.

## 9. Build the Transformer insertion demonstration

```sh
sbcl --script smc-trainer/demo/build-demo.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp \
  smc-trainer/weights/pilot-coordinate-sharded.sexp \
  smc-trainer/demo/umap-insertion-demo.html
open smc-trainer/demo/umap-insertion-demo.html
```

Expected browser check: switch between the original 90-point atlas and the
same fixed atlas with four larger, labelled synthetic profiles inserted by the
Transformer. Existing points do not move. Hovering identifies original and
predicted points. This page uses native SVG and works offline; JavaScript only
renders coordinates already calculated by Common Lisp.

The inserted profiles are deterministic demonstrations, not clinical studies
or treatment recommendations.

## 10. Documentation trail

- `README.md` describes the published map and shared programs.
- `PILOT.md` records the medical representation and pilot assumptions.
- `awrs-smc/README.md` documents the AWRS-SMC target and telemetry.
- `smc-trainer/README.md` documents corpus, training, prediction, and demo.
- `paper/` contains the manuscript and technical notes.
