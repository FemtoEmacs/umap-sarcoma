# A soft adjacency potential for AWRS-SMC UMAP search

## Motivation

V-measure evaluates whether an embedding's unsupervised clusters agree with
the declared medical classes. Homogeneity penalizes clusters that mix classes,
and completeness penalizes the fragmentation of one class across several
clusters. Neither term describes the spatial arrangement among clusters. Two
embeddings can therefore receive similar V-measure scores even when one leaves
large empty gaps between its clusters and the other places the clusters in a
more compact, visually connected arrangement.

The AWRS-SMC search adds adjacency as a preference rather than a constraint.
Separated clusters remain legal. Adjacency changes their relative probability
only at the terminal scoring step. This distinction is important: a hard rule
could eliminate a medically useful configuration, whereas a soft potential
allows the V-measure term and the adjacency term to trade off explicitly.

The ordinary search in `smc/` does not include adjacency in its target or
particle selection. The additional potential is applied by
`awrs-smc/search-umap.lisp`. Some geometry and scoring functions are shared
between the two programs, so ordinary SMC currently calculates the diagnostic
adjacency cost, but it does not use that value in its score or weights.

## Definition of adjacency cost

Let the DBSCAN procedure discover clusters

```text
C_1, C_2, ..., C_K.
```

The two UMAP coordinate columns are first standardized. This prevents an
arbitrary horizontal or vertical scale from dominating the calculation. For
each pair of clusters, their boundary distance is the smallest Euclidean
distance between any point in the first cluster and any point in the second:

```text
d(C_i, C_j) = min ||x - y||,
                  x in C_i, y in C_j.
```

For each cluster, the algorithm retains the distance to its nearest other
cluster. The gap is normalized by the DBSCAN neighborhood radius, epsilon. A
distance no greater than epsilon incurs no penalty; a larger distance incurs
only its excess over that scale:

```text
g_i = max(0, min[d(C_i, C_j)] / epsilon - 1),  j != i.
```

The adjacency cost is the mean of these nearest-cluster gaps:

```text
A = (1 / K) * sum(g_i).
```

Noise points, whose DBSCAN assignment is `-1`, are excluded. With fewer than
two discovered clusters there is no inter-cluster adjacency relation, and the
implementation returns zero for this diagnostic. V-measure continues to
penalize an uninformative single-cluster solution when the reference labels
contain several classes.

This construction uses cluster boundaries rather than centroids. Centroid
distance can be large for elongated clusters that nearly touch, even though
the visual gap between them is small. The boundary distance measures the gap
that the adjacency preference is intended to reduce.

## AWRS-SMC target

For a completed feature recipe, define

```text
Q = V - gamma * F,
```

where `V` is V-measure, `F` is the number of selected features, and `gamma` is
the feature penalty. AWRS supplies a properly weighted constrained proposal.
At the terminal step, the particle weight is multiplied by

```text
G = exp(beta * Q - lambda_A * A).
```

Here, `beta` controls the influence of the original quality score and
`lambda_A` controls the adjacency preference. The implementation names the
latter parameter `:adjacency-strength`. Setting it to zero recovers the
previous AWRS-SMC target exactly. Increasing it gives progressively more
weight to candidates with smaller normalized gaps.

The adjacency term is kept separate from the AWRS estimate of accepted
proposal mass, `Z-hat`. It is a target potential, not part of the constraint
normalizer. This preserves the interpretation of AWRS and makes the added
scientific preference visible in the result file.

## Particle diversity

The potential can distinguish only candidates that survive to terminal
evaluation. In an early pilot with four particles, resampling caused the
population to coalesce into one terminal recipe. Changing the strength of a
terminal potential cannot improve a population containing no alternative.

The adjacency pilot therefore uses 32 particles and a resampling threshold of
0.25. In the recorded seeded run, all 32 particles received terminal
evaluations and represented nine distinct UMAP recipes. These settings are not
claimed to be optimal. They make the role of the potential observable while
retaining deterministic reproduction through the declared SMC and UMAP seeds.

The current pilot settings are:

```lisp
:particles 32
:beta 8.0d0
:adjacency-strength 4.0d0
:resampling-threshold 0.25d0
:umap-seed 20260831
:smc-seed 20260901
```

The selected recipe in the recorded run had V-measure `0.692885`, a
six-feature penalty of `0.012`, quality `0.680885`, five DBSCAN clusters, and
adjacency cost `0.921102`. These values document one deterministic pilot run;
they do not establish that the chosen strength generalizes to other datasets.
A sensitivity analysis over `:adjacency-strength`, particle count, and random
seeds is required before treating the setting as a substantive empirical
result.

## Preserving the optimized layout

The potential is evaluated on coordinates produced by the dependency-free
Common Lisp UMAP implementation. Recomputing the winning feature recipe with a
different UMAP implementation can produce a different layout, even with
nominally similar parameters and a fixed seed. Earlier HTML generation kept
the winning feature recipe but discarded the coordinates on which the score
had been calculated. The browser then ran `umap-js`, so the displayed map was
not necessarily the optimized map.

AWRS-SMC now stores the winning Common Lisp coordinate array under
`:BEST :COORDINATES`, together with
`:COORDINATE-SOURCE :COMMON-LISP-UMAP`. The HTML materializer copies those
coordinates into the corresponding observations and displays them by default.
The page also retains `umap-js`. A Layout selector switches between:

1. **Winning Common Lisp coordinates**, the exact coordinates evaluated by the
   adjacency potential; and
2. **Recompute with umap-js**, a deterministic browser recomputation using the
   same winning feature recipe.

The two views answer different questions. The preserved view shows the result
selected by AWRS-SMC. The `umap-js` view tests whether the selected feature
recipe yields a qualitatively similar arrangement in a widely used independent
implementation. Agreement is useful evidence of robustness; disagreement
should be reported rather than concealed by replacing the scored coordinates.

## Reproduction

From the root of a cloned repository, run:

```sh
sbcl --script awrs-smc/search-umap.lisp \
  smc/pilot-search.sexp \
  awrs-smc/pilot-search-awrs-result.sexp

sbcl --script smc/build-best-html.lisp \
  awrs-smc/pilot-search-awrs-result.sexp \
  awrs-smc/pilot-search-awrs-best.html
```

The first command performs the constrained search and records the potential's
components, the winning coordinates, particle weights, ESS, resampling events,
and AWRS telemetry. The second command produces the dual-layout page. The
Common Lisp computation requires SBCL and the files in the cloned repository;
the `umap-js` comparison view imports its browser modules from `esm.sh` and
therefore requires network access when the page is opened.

## Interpretation and limitations

Adjacency is a presentation-oriented structural preference. It does not make
clusters more medically valid and must not be interpreted as evidence of a
biological continuum. A high strength can sacrifice label agreement or favor
maps close to DBSCAN's merging boundary. The V-measure, feature penalty,
adjacency cost, cluster count, and chosen strength should consequently be
reported separately rather than collapsed into an unexplained single score.

The cost also depends on DBSCAN epsilon and on the clustering found in the
two-dimensional embedding. It is not an invariant property of the original
high-dimensional observations. Its proper role is to steer and document the
layout search under declared assumptions, followed by sensitivity analysis and
domain review.
