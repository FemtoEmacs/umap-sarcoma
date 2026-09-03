# AWRS-SMC Parametric UMAP corpus

The corpus builder turns the winning AWRS-SMC UMAP into explicit numeric
supervision. Each S-expression record contains the frozen, standardized feature
vector under `:input` and the exact winning Common Lisp coordinates under
`:target`. It also retains the study group, train/validation split, DBSCAN
cluster, and medical label.

Build and validate it from the repository root:

```sh
sbcl --script smc-trainer/build-sharded-corpus.lisp \
  awrs-smc/pilot-search-awrs-result.sexp \
  smc-trainer/corpus/pilot-shards 25

sbcl --script smc-trainer/validate-corpus.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp

sbcl --script vendor/test-cases/run-tests.lisp \
  smc-trainer/tests.lisp

# Verify full-gradient training, one-record overfitting, and weight round-trip.
sbcl --script vendor/test-cases/run-tests.lisp \
  smc-trainer/trainer-tests.lisp

# Verify physical shard count, streaming integrity, and deterministic training.
sbcl --script vendor/test-cases/run-tests.lisp \
  smc-trainer/shard-tests.lisp

# Fit the coordinate-only baseline on the declared training split.
sbcl --script smc-trainer/train.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp \
  smc-trainer/weights/pilot-coordinate-sharded.sexp 100 0.002d0

# Supply six raw feature values in feature-schema order.
sbcl --script smc-trainer/predict.lisp \
  smc-trainer/weights/pilot-coordinate-sharded.sexp \
  '(0.8 0.1 0.2 2.0 1.0 0.3)'

# Build the clinician-facing before/after insertion demonstration.
sbcl --script smc-trainer/demo/build-demo.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp \
  smc-trainer/weights/pilot-coordinate-sharded.sexp \
  smc-trainer/demo/umap-insertion-demo.html
```

This is a distillation corpus for the numerical Transformer encoder in
`transformer.lisp`. It is not a text
corpus and does not use the llmTrainer tokenizer or its frozen token encoder.
The trainer uses dependency-free scalar automatic differentiation, seeded
initialization, and S-expression weight serialization, with full-gradient
training from numeric inputs to the two coordinate targets.

`transformer.lisp` supplies the first trainable milestone: a one-block,
single-head feature-token Transformer with scalar automatic differentiation.
Its architecture is deliberately visible as separate Common Lisp functions:
`transformer-feature-tokens`, `transformer-self-attention`,
`transformer-feed-forward`, `transformer-block`, `transformer-mean-pool`, and
`transformer-forward`. `parametric-forward` remains as a compatibility wrapper
for existing scripts and saved artifacts.
Gradients pass through the feature embeddings, scalar projection, attention,
normalization, feed-forward block, pooling, and two-coordinate regression head.
The milestone deliberately overfits one observation and saves and reloads
`weights/one-observation.sexp`; it is a gradient and serialization check, not
the final fitted atlas model.

`train.lisp` fits the coordinate-only baseline using all 70 records marked
`:train` and reports, but does not optimize against, the 20 records marked
`:validation`. The resulting artifact embeds the feature schema and frozen
preprocessing statistics. `predict.lisp` therefore accepts raw values in schema
order, applies the training-atlas standardization, and returns coordinates in
the winning Common Lisp UMAP coordinate system.

## Visual demonstration

Open `smc-trainer/demo/umap-insertion-demo.html` in a web browser. The **Atlas
view** menu switches between the original 90-point atlas and the same fixed
atlas after four illustrative profiles have been inserted. Existing observations
remain circles. The inserted profiles use four larger marked shapes and labels,
so they remain easy to identify. Hovering over any point shows whether it is an
existing observation or a Transformer prediction.

The examples are generated deterministically from the pilot feature distribution
and projected by the saved Transformer. They are explicitly labeled as synthetic
demonstrations and must not be interpreted as clinical studies or treatment
recommendations. The generated page embeds its data and uses native browser SVG;
it has no network or JavaScript-library dependency and can be opened offline.
Building it requires SBCL only. Python is not used by the builder or the page.

The validation split is grouped by study so observations from one study never
appear in both partitions. Because the target atlas itself was fitted using all
90 observations, validation measures out-of-study approximation of a fixed
atlas; it is not an independent validation of the atlas's medical structure.

## Sharded corpus

`build-sharded-corpus.lisp` writes a small manifest plus independently readable
shard files directly from the AWRS--SMC result. Its temporary sequential stream
is deleted after partitioning. Records remain in their original order,
and a study group is never divided
between shards. The record limit is therefore a soft limit when one complete
group is larger. A completed study group that reappears later in the input is
rejected. `train.lisp` streams the shards for every epoch and retains the
same deterministic global rotation on every run. Shared
feature, preprocessing, coordinate-system, and split metadata live in the
manifest. See `paper/shard.md` for the format and design rationale.
