# Choosing seeds for the AWRS-SMC search

This is a practical tutorial, not a reference. It walks through what
`:umap-seed` and `:smc-seed` actually control in `smc/pilot-search.sexp`, why
picking a "good" seed is not as simple as trusting whichever number is
already in the file, and how to use `seed-separation-sweep.lisp` to screen
candidates quickly instead of re-running the full pipeline by hand.

It grew out of a concrete case: the same repository, same seeds, same
`sarcoma-setup.x`, run on two different machines, gave two different atlases
— one with 14 real clusters, one with 12 — and one of the two mixed a
malignant tumor into a benign-tumor cluster that the other kept separate.
The rest of this document explains why that happens and what you can
actually do about it.

## 1. Two seeds, two different jobs

Both settings live in `smc/pilot-search.sexp`, in the `:search` block:

```lisp
:search (:particles 64 :beam-factor 4
         ...
         :umap-seed 20260831 :smc-seed 20260908
         ...)
```

`:umap-seed` seeds the dependency-free Common Lisp UMAP embedding step
itself — the process that takes a chosen set of numeric features for every
evidence window and lays them out in two dimensions.

`:smc-seed` seeds AWRS-SMC, the particle search that tries different
*subsets and transformations* of the available features (see
`smc/pilot-search.sexp`'s `:features` list) and scores each candidate by how
well the resulting UMAP+DBSCAN partition matches the declared sarcoma-type
labels, plus a small penalty for feature count and an optional adjacency
term. Whichever feature recipe scores best becomes "the winner," and its
embedding is what gets saved, trained on, and shown on the page.

So: `:smc-seed` decides *which features get used and how*; `:umap-seed`
decides *how those chosen features get projected into 2D*. Changing either
one can change the final map, because a different feature recipe changes
every distance in the embedding, and a different embedding random start can
land in a different local optimum even for the same features.

## 2. Seeds make a run reproducible on *one* machine — not across machines

A fixed seed guarantees that the *sequence of random draws* is identical
every time you run the search. It does not guarantee that the *floating-point
arithmetic* those draws feed into produces identical results on a different
machine. Summation order, transcendental functions like `exp` and `log`, and
compiler codegen can all differ across CPU architecture (x86_64 vs.
arm64/aarch64), operating system, and even SBCL build — and AWRS-SMC's
particle scoring depends on comparing floating-point UMAP+DBSCAN quality
numbers that aren't guaranteed bit-identical across any of those.

This is exactly what happened here: the same `smc/pilot-search.sexp`, same
`:smc-seed 20260908`, produced a clean 14-cluster atlas on one machine and a
coarser 12-cluster atlas — reproducible 3/3 times on that second machine, so
it wasn't a fluke, just a different but internally-consistent floating-point
path — on another. In the 12-cluster run, `chondrosarcoma-ivosidenib` (Tap et
al. 2020) landed only 0.0776 standardized units from the Desmoid-tumor
cluster, versus 0.0115 between Desmoid's own points — almost as close as
that cluster's own internal spacing. See
`PAZOPANIB-PLACEBO-CLUSTER-MERGE.md` for the full diagnosis; the short
version is that this was traced to the embedding itself, not a bad
clustering threshold.

**Practical consequence:** if you rebuild this repository on a new machine
and get a different cluster count or a mixing you haven't seen before,
suspect the platform before suspecting the code. Re-running with the same
seed on the *same* machine should keep giving you the same answer (that's
what determinism buys you); it's cross-machine agreement that a seed cannot
promise.

## 3. Why you can't just fix it with `:epsilon`

`:epsilon` (in the same `:search` block) sets the DBSCAN neighborhood radius
used to discover clusters from the winning embedding. Left as `:automatic`,
it's computed per run from a "knee" in the 5th-nearest-neighbor distance
distribution (`embedding-knee-epsilon` in `src/embedding-clusters.lisp`).

It's tempting to think a mixing problem like the one above can be tuned away
by picking a smaller epsilon. In the 12-cluster case, sweeping epsilon from
0.03 up through 0.90 showed there is no value that both keeps
chondrosarcoma-ivosidenib out of the Desmoid cluster *and* leaves the rest of
the atlas usable: below about 0.12, they do separate, but 56-85% of all 200
points become unclustered noise in the process; at 0.12 and above, including
the automatic pick of 0.1595, they merge again. When two points are that
close in the actual embedding, no radius threshold fixes it — the fix has to
happen upstream, in which features get selected and how they get projected.
That upstream lever is the seed.

## 4. Screening candidate `:smc-seed` values without the full pipeline

Running `sarcoma-setup.x` end to end — search, corpus build, 200-epoch
Transformer training, page render — takes real time, so trying ten seeds by
hand is slow. The AWRS-SMC search stage by itself is the ~15-20 second part;
everything after it (corpus/training/rendering) doesn't need to run at all
just to check whether a candidate seed's *embedding* keeps two groups apart.

`seed-separation-sweep.lisp` (repository root) automates exactly that check.
For each candidate seed it:

1. writes a temporary copy of `smc/pilot-search.sexp` with just `:smc-seed`
   replaced,
2. runs the AWRS-SMC search stage on that copy (`awrs-search-umap`),
3. reads the winning coordinates back out and computes that seed's own
   automatic epsilon, resulting cluster count, and whether
   `chondrosarcoma-ivosidenib` shares a DBSCAN cluster with either Desmoid
   curve, plus the standardized distance between them,
4. deletes its temporary file and moves to the next seed.

Run it from the repository root:

```
sbcl --script seed-separation-sweep.lisp
```

With no arguments it sweeps a built-in list of 24 candidates. To try
specific seeds instead:

```
sbcl --script seed-separation-sweep.lisp 20260908 20260920 42
```

Sample output (numbers will differ on your machine — that's the point):

```
seed     quality      eps    #clus  chondro/desmoid mixed?
20260908   0.6104   0.1595     14  no (min dist 0.9421)
1          0.5984   0.1609     14  YES (min dist 0.0546)
2          0.5652   0.1892     13  YES (min dist 0.1628)
...

Seeds where chondrosarcoma-ivosidenib did NOT land with Desmoid: (20260908)
```

Read the columns as:

- **quality** — AWRS-SMC's own composite score for that seed's winning
  particle (V-measure minus a feature-count penalty). Higher is generally
  better, but see the caution below.
- **eps** — that run's own automatic epsilon; different feature recipes
  produce different embeddings, so this moves from seed to seed.
- **#clus** — resulting DBSCAN cluster count at that automatic epsilon.
- **mixed?** — the one that actually matters for this specific check: did
  chondrosarcoma-ivosidenib land in the same cluster as either Desmoid
  curve? The distance in parentheses tells you how close a "no" really is —
  a "no" at 0.95 units is a comfortable margin; a "no" at 0.09 units is a
  near-miss that could flip with the next unrelated code change.

## 5. Picking a seed, and what it doesn't promise

Once you have a shortlist of seeds where the specific mixing you care about
is absent, prefer the one with the highest quality score among them — that's
the search's own measure of how well the whole atlas matches every sarcoma
type's label, not just the one pair you were checking. Put that number into
`smc/pilot-search.sexp`:

```lisp
:umap-seed 20260831 :smc-seed <your chosen seed>
```

and run the full rebuild:

```
./sarcoma-setup.x
```

Then open the generated `output/cl-sarcoma-awrs-preferences.html` and check
the actual cluster membership yourself — hover the points, or extract
`atlasPoints`/`clusterSummaries` from the page — rather than trusting the
quality score alone. A high V-measure is evidence the partition matches
labels *on average*; it does not guarantee any one specific pair of diseases
you personally care about stays apart, and it says nothing about clinical
plausibility. The chondrosarcoma/Desmoid case in this repository's history
is a reminder that a technically well-scored map can still contain one
locally troubling mixing that only a human reading the actual point list
would catch.

Two more things worth remembering:

- A seed that works on your machine is not guaranteed to work on someone
  else's, for the platform reasons in section 2. If you commit a seed
  choice, note in the commit message (or here) which machine/architecture
  verified it, so a future rebuild elsewhere that disagrees isn't a
  surprise.
- Changing `:smc-seed` can also change *which* features get selected
  entirely (not just the embedding of the same features), which can shift
  other things about the atlas besides the one mixing you were chasing.
  Always re-check the whole atlas after a seed change, not just the one
  cluster you were fixing — `seed-separation-sweep.lisp` only checks the one
  pair it was written to check.

## 6. Further reading

`PAZOPANIB-PLACEBO-CLUSTER-MERGE.md` has the full worked history this
tutorial is drawn from: the original Desmoid/chondrosarcoma mixing and its
fix (`SURVIVAL-NOT-REPORTED` as a required feature), the Hardy et al. data
truncation and its fix (`:maximum-observations` 90 → 200), the PALETTE
training-holdout bug and its fix (`:no-validation-split`), and an appendix
with the full cross-platform reproducibility diagnosis this document
summarizes in section 2-3.
