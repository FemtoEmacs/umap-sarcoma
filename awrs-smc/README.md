# AWRS-SMC UMAP search

This directory applies Adaptive Weighted Rejection Sampling (AWRS) and
Sequential Monte Carlo (SMC) to the real UMAP feature search. It is written in
dependency-free Common Lisp. It does not require Python, Node.js, or Quicklisp.

The implementation follows Definition 2 and Algorithm 2 in Lipkin et al.,
*Adaptive Weighted Rejection Sampling* (2025):

- <https://arxiv.org/abs/2504.05410>
- <https://github.com/genlm/genlm-control>

`awrs.lisp` implements AWRS with one additional trace. `smc.lisp` manages the
weighted particles, ESS, and multinomial resampling. `search-umap.lisp` joins
that algorithm to the existing Common Lisp UMAP, DBSCAN, and V-measure code.

## Search for a UMAP

From `/Users/eduardo/umap-sarcoma`, run:

```sh
sbcl --script awrs-smc/search-umap.lisp \
  smc/pilot-search.sexp \
  awrs-smc/pilot-search-awrs-result.sexp
```

The input is the same real search specification used by the earlier SMC
program. It names the database manifest, label field, UMAP settings, feature
columns, and allowed transformations. Nothing about the pilot data is
hardcoded in AWRS-SMC.

For each feature, AWRS proposes either exclusion or one of that feature's
declared transformations. The constraint enforces the minimum and maximum
feature counts. It cannot select an undeclared transformation. Each completed
particle builds a UMAP in Common Lisp, finds DBSCAN clusters, and calculates
V-measure. The score potential changes its SMC weight. The result file contains
the best real feature recipe and complete telemetry.

## Generate HTML

After the search finishes, run:

```sh
sbcl --script smc/build-best-html.lisp \
  awrs-smc/pilot-search-awrs-result.sexp \
  awrs-smc/pilot-search-awrs-best.html
```

Open `awrs-smc/pilot-search-awrs-best.html` in a browser. The builder also
writes `pilot-search-awrs-best-data.sexp` and
`pilot-search-awrs-best-problem.sexp`. Those files preserve the selected data
and settings used by the page. The browser uses its bundled `umap-js` code for
the interactive layout. The search, transformations, UMAP scoring, and winning
recipe are calculated in Common Lisp.

To start a fresh run, delete these four generated files:

```text
awrs-smc/pilot-search-awrs-result.sexp
awrs-smc/pilot-search-awrs-best.html
awrs-smc/pilot-search-awrs-best-data.sexp
awrs-smc/pilot-search-awrs-best-problem.sexp
```

Do not delete `smc/pilot-search.sexp`; it is the input specification.

## Telemetry

Telemetry is recorded inside:

pilot-search-awrs-result.sexp

Look for the top-level :TELEMETRY field. It contains:

- :PARTICLE-COUNT
- :ITERATIONS
- :INTERACTIONS
- :RESAMPLING-COUNT
- :AWRS-CONDITIONAL-DRAWS
- :CONSTRAINT-CHECKS
- :REJECTIONS
- :TERMINAL-EVALUATIONS
- :FINAL-ESS
- :NORMALIZER-ESTIMATE
- :HISTORY

The result records conditional draws, constraint checks, rejected proposals,
`psi0`, `Z-hat`, AWRS traces, particle interactions, terminal UMAP evaluations,
ESS before and after each decision, resampling events, final particle weights,
and the SMC normalizer estimate. It also records the raw V-measure-based score
for every final UMAP recipe.

## Tests

```sh
sbcl --script /Users/eduardo/.codex/skills/test-cases/scripts/run-tests.lisp \
  awrs-smc/tests.lisp
```

The tests include deterministic replay, categorical validation, unique
rejection, unbiased `Z-hat` against an exact finite calculation, the `W / M`
resampling rule, terminal score potentials, and telemetry totals.

