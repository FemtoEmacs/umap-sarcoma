# Scoring UMAPs in Common Lisp

`score-umap.lisp` builds and scores a UMAP without Python, Node.js, Quicklisp,
or a numerical library. The program runs in SBCL. It saves its result as a
Common Lisp S-expression.

The command takes a problem manifest:

```sh
sbcl --script score-umap.lisp pilot-problem.sexp
```

For this example, the result is written to:

```text
output/pilot-problem-score.sexp
```

The terminal also shows a short report. The report is for the person running
the program. The S-expression is the result that another program can read and
compare.

## The input comes from the manifest

The data path is not written into `score-umap.lisp`. The manifest declares the
file under `:data`. It also declares how each record becomes a feature vector.

For example, `pilot-problem.sexp` points to
`data/pilot-windows.sexp`. Its embedding uses the `:vector` field. The scorer
resolves the data path relative to the manifest file.

The HTML builder and the scorer use the same data reader. The reader supports
S-expressions, CSV files, and H5AD files. It checks the required fields and
unique identifiers declared in the manifest.

The manifest also contains a `:scoring` section. This section names the field
used as the medical label. It gives the DBSCAN settings, the V-measure beta,
and the output path.

Here is the scoring section from the pilot problem:

```lisp
:scoring (:label-field :sarcoma-type
          :beta 1.0
          :output "output/pilot-problem-score.sexp"
          :clustering (:algorithm :dbscan
                       :minimum-points 5
                       :epsilon :automatic))
```

## Building the UMAP

The Common Lisp implementation is in `src/common-lisp-umap.lisp`. It accepts
an array with one row per observation and one column per feature. The current
implementation produces two coordinates for each observation.

The calculation has the following steps.

### 1. Standardize the features

Each feature column is centered on its mean and divided by its sample standard
deviation. A constant column becomes zero. Standardization can be disabled in
the manifest.

### 2. Find nearest neighbors

The program calculates the Euclidean distance between every pair of rows. It
then sorts the distances and retains the requested number of nearest
neighbors.

This is exact nearest-neighbor search. It does not use an approximate index.
Exact search is simple to audit and works well for the present datasets. Its
cost grows quickly when the number of observations becomes very large.

### 3. Build the fuzzy graph

UMAP gives each observation a local distance scale. The nearest nonzero
distance becomes `rho`. The program finds `sigma` by binary search. The sum of
the local neighbor memberships is brought close to `log2(k)`, where `k` is the
number of neighbors.

For a neighbor at distance `d`, the directed membership is:

```text
1                                      when d <= rho
exp(-(d - rho) / sigma)                when d > rho
```

The membership from observation A to B may differ from the membership from B
to A. The program combines both directions with the fuzzy union:

```text
p + q - p*q
```

The result is a symmetric weighted graph. Its weights are between zero and
one.

### 4. Fit the low-dimensional distance curve

UMAP uses two constants, called `a` and `b`, in its low-dimensional distance
curve. The program fits these constants to the manifest's minimum-distance
setting. It uses a deterministic narrowing search over candidate values.

### 5. Place the points

The two-dimensional coordinates start from seeded random values between -10
and 10. The random-number generator is implemented in Common Lisp and has a
fixed seed from the manifest.

Stochastic gradient descent then moves the points. Connected points attract
each other. Random negative samples repel each other. Strong graph edges are
visited more often than weak edges. The learning rate decreases during the
run.

The fixed seed makes repeated runs deterministic on the same Common Lisp
implementation and input data.

## Finding clusters

V-measure needs a cluster number for every observation. UMAP itself does not
provide cluster numbers. `src/embedding-clusters.lisp` finds them with DBSCAN.

The program first standardizes the two UMAP coordinate columns. This prevents
the horizontal or vertical scale from controlling the distance calculation.

DBSCAN uses two settings:

- `minimum-points` is the number of nearby points needed to form dense ground.
- `epsilon` is the largest distance counted as nearby.

The manifest may give a numeric epsilon. It may also request `:automatic`.
For automatic selection, the program measures the distance from each point to
its kth neighbor, where k is `minimum-points`. It sorts these distances and
finds the knee of the curve. The distance at the knee becomes epsilon.

DBSCAN starts at an unvisited point and finds all points within epsilon. If
there are enough neighbors, it grows a cluster through neighboring dense
points. A point that does not belong to a cluster receives assignment `-1`.
The report calls these points noise.

DBSCAN does not receive the medical labels. It finds clusters only from the
two UMAP coordinates.

## Classifying the clusters

After DBSCAN has finished, the program examines the medical labels inside each
cluster. It counts each label and reports the most common one as the dominant
label.

Cluster purity is:

```text
number of observations with the dominant label / cluster size
```

A purity of 1 means that every observation in the cluster has the same label.
Purity alone is not enough. One medical class can be broken into many pure
clusters. V-measure detects this fragmentation through completeness.

## Calculating V-measure

The V-measure code is in `src/v-measure.lisp`. It builds a contingency array.
Its rows are medical labels and its columns are DBSCAN assignments, including
the noise assignment when noise is present.

The program calculates two values from this array.

Homogeneity asks whether each cluster contains observations from one medical
class. A value of 1 means that no cluster mixes classes.

Completeness asks whether all observations from one medical class are placed
in the same cluster. A value of 1 means that no class is split across
clusters.

V-measure is the weighted harmonic mean of homogeneity and completeness:

```text
V = (1 + beta) * homogeneity * completeness
    / (beta * homogeneity + completeness)
```

The default beta is 1. This gives equal weight to homogeneity and
completeness. A larger beta gives more weight to completeness. It therefore
penalizes fragmentation more strongly.

Consider a map with four sarcoma types and fifteen single-color clusters. Its
homogeneity can be close to 1 because the colors do not mix. Its completeness
will be lower because each sarcoma type appears in several clusters. The
V-measure will reflect both facts.

## What the saved file contains

The output S-expression records:

- the manifest and data paths;
- the label field;
- the UMAP parameters;
- the number of observations and input features;
- the two-dimensional coordinate array;
- the DBSCAN settings and assignment vector;
- the number of clusters and noise points;
- each cluster's size, label counts, dominant label, and purity;
- homogeneity, completeness, V-measure, and the contingency array.

This file can be read with ordinary Common Lisp:

```lisp
(with-open-file (stream "output/pilot-problem-score.sexp")
  (let ((*read-eval* nil))
    (read stream)))
```

No JavaScript is needed to calculate or inspect the saved result. The browser
can still build the interactive display with `umap-js`. That display is a
separate use of the same manifest and evidence records.

## Repeating the calculation for another problem

A new problem needs a manifest with `:data`, `:preprocessing`, `:umap`, and
`:scoring` sections. The command stays the same:

```sh
sbcl --script score-umap.lisp another-problem.sexp
```

If the manifest does not declare an output path, the scorer uses:

```text
output/another-problem-score.sexp
```

The program does not assume a sarcoma dataset, 600 observations, or 23
features. Those values come from the input selected by the manifest.
