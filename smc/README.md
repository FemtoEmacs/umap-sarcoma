# Lew SMC for UMAP feature search

This directory contains a dependency-free Common Lisp implementation. It
searches for a subset of input features and a valid transformation for each
selected feature. It then builds and scores each proposed UMAP in Common Lisp.

The search file is data. Each feature has a column number and an explicit list
of allowed transformations. The program can also exclude a feature. It cannot
invent another transformation. For example, `:log1p` is only safe when the
declared feature cannot be negative. Runtime checks stop the search if a
declaration is wrong.

Run the pilot search from the repository root:

```sh
sbcl --script smc/search-umap.lisp smc/pilot-search.sexp
```

From this folder, you must type:

```sh
sbcl --script search-umap.lisp pilot-search.sexp
```

The result is written to `smc/pilot-search-result.sexp`. Its `:best` field is
the best configuration seen during the whole run. The file also records the
search settings, SMC history, final particles, and selected features. The pilot limits the data
to 90 observations and uses short UMAP runs. Those values make it useful for
testing the idea. Remove the observation limit and increase the UMAP epochs for
a real search.

Build an HTML page for the winning recipe (from the repository root):

```sh
sbcl --script smc/build-best-html.lisp smc/pilot-search-result.sexp \
  smc/pilot-search-best.html
```

From the smc folder:

```sh
sbcl --script build-best-html.lisp pilot-search-result.sexp pilot-search-best.html
```


This also writes `pilot-search-best-data.sexp` and
`pilot-search-best-problem.sexp` beside the HTML file. They preserve the exact
selected columns, transformations, observation limit, and UMAP settings used
for the page. The browser performs the visual UMAP layout with `umap-js`; all
feature selection and transformations are materialized beforehand by Common
Lisp.

## Algorithm

The implementation uses the SMC steering procedure published by Alexander K.
Lew and colleagues and the equations in the authors' LLaMPPL reference code.
It maintains `N` particles. A particle is a partial sequence of feature
decisions. Each active particle produces `K` children at the next feature.

The proposal `Q` is uniform over the decisions that can still satisfy the
declared feature-count limits. The declared prior `P` is the same distribution.
The program records both log probabilities and applies `log P - log Q`. At the
last feature, it builds the UMAP, finds DBSCAN clusters, and calculates
V-measure. The final potential is `exp(beta * score)`. Thus the target is the
prior over valid recipes multiplied by this score potential.

After each `N * K` expansion, the program uses the optimal resampling procedure
in Lew's code. It solves for `c`, retains particles with `c * weight >= 1`
deterministically, selects the rest by stratified sampling, and applies Lew's
separate post-resampling weight corrections to the two groups.

Primary references:

- Alexander K. Lew, Tan Zhi-Xuan, Gabriel Grand, and Vikash K. Mansinghka,
  "Sequential Monte Carlo Steering of Large Language Models using
  Probabilistic Programs," 2023: <https://arxiv.org/abs/2306.03081>
- Authors' LLaMPPL implementation: <https://github.com/probcomp/llamppl>

The earlier local AWRS-SMC implementation supplied reusable Common Lisp
machinery. The exact optimal-resampling equations were recovered from the
authors' LLaMPPL implementation. The UMAP code changes the probabilistic model,
but not Lew's SMC inference procedure.

## Tests

The tests use the dependency-free `test-cases` runner:

```sh
sbcl --script ~/.codex/skills/test-cases/scripts/run-tests.lisp \
  /Users/eduardo/umap-sarcoma/smc/tests.lisp
sbcl --script ~/.codex/skills/test-cases/scripts/run-tests.lisp \
  /Users/eduardo/umap-sarcoma/smc/integration-tests.lisp
```

They check deterministic randomness, feature-count bounds, proposal and prior
probabilities, the defining equation for Lew's resampling threshold, distinct
resampling, stable log weights, transformation whitelists, and complete runs.
