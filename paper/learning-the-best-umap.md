# Learning the Best UMAP

## Purpose

A UMAP depends on choices made before the points appear on the screen. We must
choose the input features. We may also transform some features. Different
choices can produce very different maps.

The program in `smc/` searches these choices. It builds candidate UMAPs in
Common Lisp and gives each one a score. It uses Sequential Monte Carlo (SMC) to
sample feature sets. The current implementation follows the SMC steering method
published by Alexander K. Lew and colleagues [1].

The browser is not part of this learning step. Common Lisp prepares the data,
builds each candidate UMAP, finds its clusters, and calculates its score. After
the search, a separate command can make an interactive HTML page for the best
recipe.

## Input data

The search starts with a UMAP problem manifest. The pilot search points to
`pilot-problem.sexp`. That manifest points to the evidence records. The paths
are read from the files. They are not built into the Lisp program.

Each observation has a numeric vector. A row in the array is one observation.
A column is one possible feature. The pilot vector contains survival values,
response rates, follow-up, cohort size, and other evidence measurements.

The search file names the columns that SMC may use. It also lists the allowed
transformations for each column. Here is a short example:

```lisp
(:name :objective-response-rate
 :column 13
 :transformations (:identity :protected-logit))
```

SMC may exclude this feature. If it includes the feature, it must use
`:identity` or `:protected-logit`. It cannot propose a logarithm or another
undeclared operation.

This rule protects the data. For example, ordinary `:log1p` rejects a negative
number. A signed measurement can instead declare `:signed-log1p` or `:asinh`.
The integration test applies every declared transformation to every value in
its column. A bad declaration stops the test.

## Why we use S-expressions

The configuration and result files use S-expressions. An S-expression is an
atom or a list containing more S-expressions. This form fits nested scientific
records without a separate parser library.

Ronald Rivest described S-expressions as a representation for lists and byte
strings. His specification sought a form that was easy to parse and easy to
extend [2]. Our files use ordinary readable Common Lisp syntax rather than the
canonical byte-string form in Rivest's specification. The shared idea is a
small tree representation with explicit structure.

The search file is data. It is not executable Lisp code. The reader binds
`*read-eval*` to `nil`. Reader evaluation is therefore disabled.

A shortened search description looks like this:

```lisp
(:format :umap-smc-search
 :version 1
 :manifest "../pilot-problem.sexp"
 :label-field :sarcoma-type
 :search (:particles 4
          :beam-factor 3
          :minimum-features 2
          :maximum-features 6
          :beta 8.0d0
          :maximum-observations 90
          :epochs 35
          :smc-seed 20260901)
 :features
 ((:name :local-drop
   :column 5
   :transformations (:identity :protected-logit))
  (:name :event-code
   :column 22
   :transformations (:identity))))
```

The file states the full search boundary. A reader can see the particle count,
the feature limits, the seed, and every permitted transformation.

## A particle

A particle holds a partial list of decisions. The first decision belongs to
the first declared feature. The next decision belongs to the next feature.
The value is `:exclude` or the name of an allowed transformation.

For example, a partial particle may contain:

```lisp
(:exclude :identity :protected-logit)
```

The particle has dealt with three features. It excluded the first feature,
kept the second unchanged, and applied a protected logit to the third.

The particle also stores a log weight. Log weights prevent overflow when many
probabilities are multiplied.

## The sequential probabilistic model

The program visits the feature declarations in order. At each feature, it
finds the decisions that can still satisfy the feature-count limits. Suppose a
particle has already reached the maximum. Its only legal next decision is
`:exclude`. Suppose it must select every remaining feature to reach the
minimum. Exclusion is then illegal.

The proposal distribution, called `Q`, is uniform over the legal decisions.
The prior distribution, called `P`, is the same. The program records both
probabilities and adds this importance term to the log weight:

```text
log P(decision) - log Q(decision)
```

The term is zero in the present model because `P` and `Q` are equal. Writing it
explicitly is still important. We can later introduce a medical prior or a
better proposal without changing the SMC equations.

## Lew's SMC step

Let `N` be the number of particles and `K` the beam factor. Each active particle
produces `K` children. The temporary population therefore contains `N * K`
particles. Each child samples one legal feature decision.

Lew's algorithm adjusts the child weights for this expansion. It then reduces
the temporary population to `N` particles. It uses the optimal resampling rule
of Fearnhead and Clifford [3].

The resampler finds a number `c` that satisfies:

```text
sum over i of min(1, c * weight[i]) = N
```

A particle with `c * weight[i]` at least 1 survives. The choice is
deterministic. The remaining places are filled by stratified sampling. The
selected particles receive the post-resampling weights given in Lew's
algorithm.

The implementation tests the equation for `c` with an independent oracle. It
also checks that resampling returns exactly `N` distinct children.

## Building and scoring a candidate

The current model scores a particle after its last feature decision. This
leaves the earlier SMC steps free of UMAP cost. It also means that the early
weights are equal. The medical score affects the final resampling step.

For each complete recipe, Common Lisp performs these operations:

1. Select the declared columns.
2. Apply the chosen transformations.
3. Standardize the selected columns when requested.
4. Build a two-dimensional UMAP.
5. Find clusters with DBSCAN.
6. Compare the cluster assignments with the medical labels.
7. Calculate V-measure.

UMAP follows the method introduced by McInnes, Healy, and Melville [4]. The
implementation used here is in `src/common-lisp-umap.lisp`. DBSCAN does not see
the medical labels. It only receives the two UMAP coordinates.

V-measure combines homogeneity and completeness [5]. Homogeneity falls when a
cluster mixes medical classes. Completeness falls when one medical class is
split among several clusters. This matches the main aim of the search: find
clusters with consistent colors without creating too many fragments.

The quality used by SMC is:

```text
quality = V-measure - feature-penalty * selected-feature-count
```

The small feature penalty favors a simpler recipe when two candidates have
similar V-measure. It is declared in the search file.

The last observation in the probabilistic model has this potential:

```text
exp(beta * quality)
```

The final target distribution is the prior probability of a valid recipe
multiplied by this potential. A larger `beta` places more probability on
higher-scoring maps.

## The result S-expression

The search writes `pilot-search-result.sexp`. The file contains the winning
recipe and the complete audit record. Its top level includes:

- the search and problem file paths;
- the algorithm name;
- links to Lew's paper and reference implementation;
- the probabilistic model;
- the search settings and seeds;
- the number of UMAP evaluations and cache hits;
- one history record for each feature step;
- the best recipe seen during the run;
- the final particle population and weights.

The `:best` record has this form:

```lisp
(:best
 (:score 0.7394780154754805d0
  :features
  ((:name :survival-next
    :column 1
    :transformation :identity)
   (:name :local-drop
    :column 5
    :transformation :identity))))
```

The actual file can contain more selected features. This shortened example
shows the representation.

The result is read as data:

```lisp
(with-open-file (stream "smc/pilot-search-result.sexp")
  (let ((*read-eval* nil))
    (read stream)))
```

No Python, Node.js, Quicklisp package, or database library is needed.

## Running the learner

From the repository root, run:

```sh
sbcl --script smc/search-umap.lisp smc/pilot-search.sexp
```

The fixed SMC and UMAP seeds make the pilot repeatable with the same SBCL,
input files, and settings.

The pilot uses 90 observations and 35 UMAP epochs. These limits make a quick
test possible. A study run should use the intended observations and enough
epochs for the final analysis. The search file controls both values.

## Making the HTML page

The result S-expression is not an image. It contains the winning recipe. To
make a page for that recipe, run:

```sh
sbcl --script smc/build-best-html.lisp \
  smc/pilot-search-result.sexp \
  smc/pilot-search-best.html
```

Common Lisp writes two supporting files. The data file contains the selected
and transformed feature vectors. The problem file contains the display
settings. The HTML page reads those materialized values.

The browser uses `umap-js` to draw an interactive layout. This browser layout
is for inspection. The SMC score came from the Common Lisp UMAP built during
the search.

## Reading the result with care

SMC is a sampling method. One run does not examine every possible feature
recipe. More particles or a larger beam give broader coverage and require more
UMAP calculations.

The present learner applies the score only at the terminal step. This is an
exact use of Lew's SMC inference method for the probabilistic model stated
above. It is a simple first model. A later version could add valid intermediate
potentials. Such a change would need a new written target distribution and new
tests.

The best score belongs to the data, label field, transformations, UMAP
settings, clustering settings, and seed recorded in the result. Another study
may choose a different recipe. That is why the program saves the full search
record instead of saving only a picture.

## References

1. Alexander K. Lew, Tan Zhi-Xuan, Gabriel Grand, and Vikash K. Mansinghka.
   "Sequential Monte Carlo Steering of Large Language Models using
   Probabilistic Programs." 2023. <https://arxiv.org/abs/2306.03081>

2. Ronald L. Rivest. "S-Expressions." Internet Draft, May 4, 1997.
   <https://datatracker.ietf.org/doc/html/draft-rivest-sexp-00.txt>

3. Paul Fearnhead and Peter Clifford. "On-line inference for hidden Markov
   models via particle filters." *Journal of the Royal Statistical Society:
   Series B*, 65(4), 2003, pages 887–899.
   <https://doi.org/10.1111/1467-9868.00421>

4. Leland McInnes, John Healy, and James Melville. "UMAP: Uniform Manifold
   Approximation and Projection for Dimension Reduction." 2018.
   <https://arxiv.org/abs/1802.03426>

5. Andrew Rosenberg and Julia Hirschberg. "V-Measure: A Conditional
   Entropy-Based External Cluster Evaluation Measure." EMNLP-CoNLL, 2007.
   <https://aclanthology.org/D07-1043/>
