# Sharded training corpus

The `smc-trainer` can store its annotated corpus as independently readable
Common Lisp shards. It uses a repository-local count-bounded sequential
algorithm adapted to the AWRS–SMC UMAP corpus. The purpose is bounded-memory,
reproducible training as the number of studies grows.

The established family name is **range-based sharding**. “Count-bounded
sequential sharding at study-group boundaries” is a descriptive name for this
project's variant, rather than the formal name of a separately published
algorithm.

The canonical pilot corpus consists of a manifest and five physical shard files.
The build leaves no monolithic corpus artifact. This establishes a stable format
for larger corpora assembled by genAI and reviewed by researchers.

## Format

`manifest.sexp` is one property list containing the corpus-wide feature schema,
preprocessing statistics, split policy, total record count, and ordered shard
descriptors. Each descriptor names a shard, its record count, and its study
groups. Each shard contains consecutive top-level record property lists. A reader
therefore calls Common Lisp `READ` once per observation and holds only the current
record.

Study records must be contiguous in the source stream. The sharder retains only
the current group and a set of completed group names. It rejects a completed group
that reappears and rejects a group assigned to conflicting splits. Original
record order is preserved exactly and study groups remain indivisible. The
requested record limit is a soft bound: a group
larger than the limit occupies one larger shard. This preserves the study-grouped
training and validation policy and prevents windows from one study from being
silently separated by the storage layout.

## Determinism

Manifest order and record order reproduce the original corpus order. During an
epoch, `train.lisp` applies the same global deterministic rotation as the
training implementation. It obtains that rotation with two sequential passes
over the shards, beginning at the epoch offset and then wrapping to the start.
Consequently, sharding changes storage and memory use without changing the Adam
update sequence.

The regression suite requires at least three nonempty physical shards and trains
twice from the same seed, requiring identical model forms and reports.

## Commands

From the repository root:

```sh
sbcl --script smc-trainer/build-sharded-corpus.lisp \
  awrs-smc/pilot-search-awrs-result.sexp \
  smc-trainer/corpus/pilot-shards 25

sbcl --script smc-trainer/validate-corpus.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp

sbcl --script smc-trainer/train.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp \
  smc-trainer/weights/pilot-coordinate-sharded.sexp 100 0.002d0

sbcl --script vendor/test-cases/run-tests.lisp \
  smc-trainer/shard-tests.lisp
```

The implementation uses SBCL and repository files only. It introduces no Python,
database, Quicklisp, or binary corpus dependency.

## Limitations

The implementation deliberately favors inspectability over input speed. The
global rotation requires two passes over the training shards per epoch, and
metric reporting requires further passes. This remains suitable for the present
small Transformer. A later optimization could maintain a bounded deterministic
shuffle buffer, provided an equivalence or explicitly versioned ordering policy
is retained.
