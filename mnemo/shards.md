# Memory: sharded AWRS–SMC Transformer corpus

Read this note before answering questions or changing shard code in
`umap-sarcoma`. It records the implemented design and prevents confusion between
a stream file, a manifest, and a physical shard.

## Current state

The canonical clinical corpus is
`smc-trainer/corpus/pilot-shards/manifest.sexp`. The repository should not need
`smc-trainer/corpus/pilot-parametric-umap.sexp`; that former monolithic artifact
was removed. The manifest currently names five physical shards containing 20,
20, 20, 20, and 10 records. The 90-record total describes the present pilot and
is not an algorithmic requirement.

Training and demo generation must receive the manifest path. Both traverse every
descriptor in manifest order and every record in each shard. A shard contains
successive top-level property lists, so Common Lisp invokes `READ` once per
record. `parametric-map-shard-file` does not construct a list of shard records.

## Programs and responsibilities

- `smc-trainer/build-sharded-corpus.lisp` is the canonical entry point. It takes
  an AWRS–SMC result, creates a temporary sequential corpus, invokes the sharder,
  and removes the temporary file with `UNWIND-PROTECT`.
- `smc-trainer/build-corpus.lisp` derives standardized feature vectors, preserved
  winning coordinates, labels, clusters, and study-grouped splits. It writes the
  temporary header followed by top-level records. It remains an internal stage of
  the direct shard build.
- `smc-trainer/shard-corpus.lisp` implements count-bounded sequential allocation
  at verified study boundaries and writes the manifest.
- `smc-trainer/shards.lisp` is the shared reader. It recognizes legacy
  single-form corpora, sequential stream corpora, and shard manifests. Canonical
  operation uses the manifest branch.
- `smc-trainer/validate-corpus.lisp` streams all shards and checks declared count,
  unique identifiers, numeric dimensions, finite values, positive scales, and
  consistent study splits.
- `smc-trainer/train.lisp` streams the manifest repeatedly. It preserves the
  deterministic epoch rotation with two ordered passes and does not load the
  corpus into a training list.
- `smc-trainer/demo/build-demo.lisp` reads all manifest shards to assemble the
  browser artifact, then projects four illustrative points with saved Transformer
  weights. Collecting records here is acceptable because the final HTML embeds
  every displayed atlas point.
- `smc-trainer/shard-tests.lisp` tests physical shard count, variable corpus
  size, deterministic training, study contiguity, and split consistency.
- `smc-trainer/tests.lisp` tests the current clinical corpus and its group split.
- `paper/shard.md` is collaborator-facing documentation. This file is internal
  project memory and may be more explicit about implementation details.

## Allocation algorithm

Use **range-based sharding** as the established algorithm-family name. The phrase
“count-bounded sequential sharding at study-group boundaries” is a local,
descriptive label for this implementation, not the published name of a standard
algorithm. Sequential reading and size-bounded shard writing are common dataset
engineering techniques; the study-boundary rule is specific to this corpus.

`shard-map-study-groups` reads the source sequentially. It retains the current
study's records plus a hash set containing only completed study names. When the
study changes, it emits the completed group. A completed name that appears again
causes an error; this prevents an interleaved study from being divided silently.
A split change inside one study also causes an error.

`shard-corpus` keeps one output stream open. Before writing a complete group, it
checks whether `current-shard-count + group-size` exceeds the configured soft
limit. If so, it closes the current shard, records its descriptor, and opens the
next numbered shard. A study larger than the limit occupies one larger shard;
study integrity has priority over the numerical limit. Record order is unchanged.

The manifest stores shared feature and preprocessing metadata, total record
count, soft record limit, group-preservation flag, source-order flag, and ordered
descriptors. Each descriptor stores the relative filename, physical record count,
and study names. Relative filenames keep a clone self-contained.

Memory during sharding is proportional to the largest study group plus the number
of completed study names and manifest descriptors. Memory during training is
independent of the number of records, aside from the fixed model and optimizer.
Validation retains record identifiers to detect duplicates, so validation memory
currently grows with record count.

## Invariants and tests

The current clinical test expects 90 because loss of one of the available pilot
records is a regression. The general variable-size test builds seven synthetic,
nonclinical records and obtains three physical shards with counts 2, 3, and 2.
This establishes that the algorithm does not require 90 records.

Required invariants are: at least one training record; manifest count equals the
number physically read; record IDs are unique; every input has the declared
feature dimension; every target has two finite coordinates; preprocessing scales
are positive; one study belongs to one split; a completed study never reappears;
and shard iteration follows manifest order.

## Canonical commands

From the repository root:

```sh
sbcl --script smc-trainer/build-sharded-corpus.lisp \
  awrs-smc/pilot-search-awrs-result.sexp \
  smc-trainer/corpus/pilot-shards 25

sbcl --script smc-trainer/validate-corpus.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp

sbcl --script vendor/test-cases/run-tests.lisp smc-trainer/tests.lisp
sbcl --script vendor/test-cases/run-tests.lisp smc-trainer/shard-tests.lisp
sbcl --script vendor/test-cases/run-tests.lisp smc-trainer/trainer-tests.lisp

sbcl --script smc-trainer/train.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp \
  smc-trainer/weights/pilot-coordinate-sharded.sexp 100 0.002d0

sbcl --script smc-trainer/demo/build-demo.lisp \
  smc-trainer/corpus/pilot-shards/manifest.sexp \
  smc-trainer/weights/pilot-coordinate-sharded.sexp \
  smc-trainer/demo/umap-insertion-demo.html
```

## Cautions for future changes

Do not describe the former large source stream as a shard. Do not fabricate or
duplicate clinical observations merely to increase a shard count; use the
clearly labeled synthetic variable-size test. Preserve study boundaries before
optimizing shard balance. Run the complete pipeline after changing formats,
reader traversal, group allocation, training order, or filenames.

The build currently materializes derived records while extracting them from the
AWRS–SMC result, then writes and removes a temporary stream. Shard conversion and
training are record-streaming. If the upstream AWRS–SMC result becomes extremely
large, `build-corpus.lisp` will need a callback-based extraction refactor as a
separate scalability improvement.
