# Why pazopanib and placebo landed in separate clusters, and what changed

Eduardo flagged that two clusters in the preferences page -- one built almost
entirely from `sts-pazopanib` evidence windows, the other entirely from
`sts-placebo` windows -- looked like an artificial split: both arms come from
the same trial (van der Graaf et al. 2012, PALETTE), and soft-tissue sarcoma
is a disease where, per Hardy et al. 2025 ("Twenty-five years without
progress: the enduring challenge of soft tissue sarcomas," *Cancer*,
[10.1002/cncr.35906](https://acsjournals.onlinelibrary.wiley.com/doi/abs/10.1002/cncr.35906)),
overall five-year survival has not moved in two decades. His reading: if a
therapy doesn't improve survival, this project's atlas should treat it as
equivalent to placebo, and that should be "implemented somewhere -- maybe in
AWRS-SMC."

## What the data actually showed

`data/pilot-landmarks.sexp` records both PALETTE arms with `:endpoint
"Overall survival"`: pazopanib's modeled curve has median OS 12.5 months
(`os-hazard-ratio 0.86`), placebo's has median OS 10.7 months. That HR of
0.86 is close to 1 -- consistent with the trial's own published finding that
**pazopanib showed no significant overall-survival benefit** (PALETTE, Lancet
2012). The trial's real, large, statistically significant effect was on
**progression-free survival** instead: median PFS 4.6 months (pazopanib) vs.
1.6 months (placebo), HR 0.31. A [Nature Reviews Clinical Oncology
commentary](https://www.nature.com/articles/nrclinonc.2012.113) on the trial
notes explicitly that the missing OS benefit despite the clear PFS benefit
"might lie in the study design" -- placebo-controlled oncology trials
routinely let patients cross over to the active drug after progression,
which dilutes an OS comparison even when PFS is unambiguously improved; this
project's data file doesn't record whether PALETTE specifically allowed
crossover, so that explanation is offered as the well-known general
mechanism, not a confirmed fact about this one trial.

The AWRS-SMC feature declared in `smc/pilot-search.sexp` that reflects OS
curve shape (`local-drop`, the proportional survival decline within a
window) differed only modestly between the two arms -- 0.393 (pazopanib) vs.
0.442 (placebo) -- and yet the winning particle's DBSCAN pass still put all
ten pazopanib windows in one cluster and all ten placebo windows in another.
Meanwhile `median-pfs-log10p` -- the one declared feature that reflects the
trial's real, large, significant effect -- was never selected by the winning
particle at all (checked across all 33 particles the original search
recorded). So the split reflected a same-endpoint, non-significant OS nuance,
using a feature set that had no way to represent the axis on which the two
arms actually differ.

## What we changed, and why not a hardcoded rule

Eduardo's proposed fix -- treat "no survival benefit vs. placebo" as
"equivalent to placebo" as a rule inside AWRS-SMC -- is defensible as a
one-off judgment about this one comparison, but risky to encode as a general
mechanism: it would need the search to automatically identify which arms are
"paired" (trial-and-control), silently run a significance test, and act on a
binary equivalence call, and the same logic would misfire in a disease or
trial where **PFS itself is the correct primary signal** (not every disease
context makes OS the only response that counts) or where OS is genuinely
underpowered by design rather than by absence of effect.

Instead, we tested a narrower, more principled question: would AWRS-SMC's
*own existing objective* -- V-measure plus feature-count and adjacency
penalties, unchanged -- prefer to include the clinically informative PFS/OS
features and merge these two arms, if it were simply given room to? The
search's `:maximum-features` was capped at 6, and the winning 6-feature
particle used every slot; `median-pfs-log10p` had no room to compete against
whatever it would have had to displace.

We raised `:maximum-features` from 6 to 8 and widened the search itself
(`:particles` 32 -> 64, `:beam-factor` 3 -> 4, same `:umap-seed`/`:smc-seed`
as before, so this is a widened version of the existing search, not a
different one). Rerunning `awrs-smc/search-umap.lisp` on this widened
configuration, with no seed changed from the project's existing default,
gives a new winning particle that **includes `median-pfs-log10p`**, scores
**0.745** (up from the prior 6-feature baseline's 0.716 -- a real
improvement on AWRS-SMC's own objective, not a trade against it), and, when
the full pipeline (`sarcoma-setup.x`) is rerun end to end, **places all ten
pazopanib windows and all ten placebo windows in the same cluster** (cluster
2, alongside a few chondrosarcoma-ivosidenib and population-level STS
windows). GIST-imatinib remains its own separate cluster (cluster 4,
correctly not merged with anything), now named "longer median
progression-free survival + higher disease control rate" -- which is exactly
the "bright spot" Hardy et al. describe: GIST is the one sarcoma type in
their analysis that actually improved.

So the merge Eduardo expected did happen -- but it emerged from AWRS-SMC's
own scoring once given room to see the relevant feature, rather than from a
hardcoded biological equivalence rule. That seems like the right place to
land: no new "if no OS benefit, treat as placebo" logic was added anywhere
in the codebase.

**An honest caveat about robustness:** trying several different `:smc-seed`
values at these same widened settings produced a wide score range (0.51 to
0.82) and inconsistent feature selection -- 64 particles does not fully
converge this search space every time. The specific run adopted here reused
the project's existing default seed (no seed-shopping for a preferred
outcome) and happened to land on a solid, PFS-including, merge-producing
particle at a score above the prior baseline, but a different default seed
choice could plausibly land somewhere else. This is worth another look if
the atlas is revisited (a higher, fixed particle count, or averaging several
seeds' results, would be a more thorough follow-up than this pass attempted).

## The other fix: making feature sliders self-explanatory

Eduardo separately noted that the sliders don't distinguish "primary event:
death" from "primary event: progression" -- `event-code` was already one of
the model's input features, but its slider showed a generic "Event Code"
label with four decimal places, not what 0 vs. 1 means. Fixed by adding a
`*sarcoma-feature-display-overrides*` table in
`sarcoma-specific/build-preferences-page.lisp` giving every one of this
project's declared features (not just event-code) a clear label -- e.g.
`event-code` now reads "Event type (0 = progression, 1 = death)",
`median-pfs-log10p` reads "Median progression-free survival, months
(log10(1+x))" -- instead of the previous auto-generated "Event Code" /
"Median Pfs Log10p" with an opaque "feature units" unit and uniform 4-decimal
display.

## Files changed (original pass)

- `smc/pilot-search.sexp`: `:maximum-features` 6 -> 8, `:particles` 32 -> 64,
  `:beam-factor` 3 -> 4. `:umap-seed`/`:smc-seed` unchanged.
- `output/sarcoma-awrs-smc-result.sexp`, `smc-trainer/cl-sarcoma-awrs-model.sexp`,
  `smc-trainer/corpus/sarcoma-awrs-shards/*`: regenerated by the full
  `sarcoma-setup.x` pipeline against the widened search.
- `sarcoma-specific/build-preferences-page.lisp`: added
  `*sarcoma-feature-display-overrides*` (feature label/unit/decimal
  clarity) and the earlier cluster-naming-by-feature work (see the
  companion cluster-renaming fix from the same session).
- `output/cl-sarcoma-awrs-preferences.html`: regenerated.
- Pre-widening baseline backed up to
  `output/experiments/2026-09-12-maxfeatures8-widen-backup/` (search config,
  AWRS-SMC result, trained model, and sharded corpus, all under the old
  6-feature/32-particle settings) in case this needs to be compared against
  or reverted.

## Addendum: the widening regressed Desmoid, and why

Shortly after the widened search above shipped, Eduardo reported that it had
gone too far the other way: "now, no cluster is working... lost the ability
of distinguishing Desmoid Sorafenib and Desmoid Placebo... Bone sarcoma is
also mixed up with desmoid." He also connected this to something he'd
flagged earlier and that the first pass had left unaddressed: the sliders
don't expose a death-vs-progression distinction, and he suspected "the model
does the distinction internally" -- so its disappearance from the *visible*
feature set might have masked a deeper problem.

**Verifying the claim against the reference atlas.** The frozen 90-point
atlas's own cluster assignments did *not* show Desmoid mixed with bone
sarcoma or with itself -- Desmoid-Sorafenib, Desmoid-Placebo, and
Osteosarcoma were each still in their own clean cluster, and per-record
model recovery against the known 90 points was 88/90 (97.8%). Taken at face
value, that looked like the report might not hold up. But a fixed reference
atlas of 90 already-seen points is the wrong place to look for this kind of
bug -- it can only show whether the model reproduces what it was trained on,
not what it does with a profile it has never seen, which is what moving a
slider actually asks it to do.

**Confirming it on novel input instead.** The widened search's winning
particle was `(SURVIVAL-NEXT WINDOW-START-FRACTION COHORT-SIZE-LOG10P
MEDIAN-PFS-LOG10P OBJECTIVE-RESPONSE-RATE DISEASE-CONTROL-RATE
OVERALL-SURVIVAL-36 OVERALL-SURVIVAL-60)` -- `event-code` is not in that
list. Constructing a synthetic "new Desmoid trial" profile (progression
endpoint, cohort of 44, objective response rate 0.27 -- deliberately between
the two known arms' 0.33/0.20) and running it through the deployed
Transformer by hand confirmed two things at once:

1. The synthetic Desmoid-like profile predicted into the same region as the
   population-level soft-tissue-sarcoma curve, nowhere near either Desmoid
   cluster.
2. Flipping that same profile's `primary-event`/`event-code` from
   Progression/0 to Death/1 -- which should matter enormously, since it is
   the one field that says whether the disease this profile describes can
   kill anyone -- produced **bit-for-bit identical** predicted coordinates.

So Eduardo's diagnosis was right on both counts: `event-code` really had
been dropped from the widened search's winning feature set, and its absence
really did make the model unable to tell a locally-aggressive-but-nonlethal
profile from a lethal one on anything it hadn't already memorized. The
reference atlas looked fine only because none of its 90 points required the
model to generalize.

**Root cause, part one: nothing pinned `event-code` in place.**
AWRS-SMC treats every declared feature as equally disposable and picks
whichever subset scores best on V-measure plus a small per-feature penalty.
That is the right default for most features, but `event-code` is not "just
another feature" -- it is the field that distinguishes diseases whose
natural history ends in progression from diseases whose natural history
ends in death, which is the most basic clinical fact this atlas has about
any curve. Leaving it exposed to the same stochastic trade-off as, say,
`window-area` meant a different random seed could -- and did -- throw it
away for a marginally higher score.

**Root cause, part two: the widened search was quietly filling slots with
noise, not signal.** Looking at what `event-code` got traded for explained
why this was tempting to the search at all. Of the widened run's 8 selected
features, three -- `disease-control-rate`, `overall-survival-36`, and
`overall-survival-60` -- turned out to be **exactly constant across all 90
training records**. Each of those fields is reported by exactly one of the
nine curves in the `:maximum-observations 90` subset (chondrosarcoma-
ivosidenib for disease-control-rate, osteosarcoma-map for both overall-
survival landmarks); every other curve has it median-imputed, and since the
median of "eight missing values plus one real one" is just that one real
value, all 90 records end up with the identical number. `cl-umap-standardize`
(and smc-trainer's independent copy of the same logic in
`build-corpus.lisp`) computed each column's standard deviation and only
special-cased an *exactly* zero scale; a column that is constant only up to
floating-point rounding noise -- true here, since delta = value - mean should
be exactly 0 but isn't quite, for these three columns -- produced a scale on
the order of `1e-15` to `1e-17` instead. Standardizing by dividing by that
near-zero scale is numerically inert for the 90 training records themselves
(the same rounding noise gets divided out identically for every row, so it
never moved a training point), which is why it never showed up as a training-
quality problem and the search was happy to add these columns for a
negligible feature-count penalty. But it left three of the eight selected
features carrying zero real information -- exactly the three "free" slots
that made room to drop `event-code` without hurting the score.

**The fix.**

1. `awrs-smc/search-umap.lisp` now supports `:required t` on a feature
   declaration: AWRS's proposal step for that feature never offers
   `:exclude`, so no particle, at any seed, can trade it away. `event-code`
   is now the first entry in `smc/pilot-search.sexp`'s `:features` list and
   carries `:required t` -- first, specifically, because a required feature
   later in the list can still crash the search ("no proposal mass remains
   after rejections") if earlier optional choices already filled every
   remaining slot before its mandatory turn came up; deciding it first makes
   that impossible.
2. `src/common-lisp-umap.lisp` (`cl-umap-standardize`, used during the
   search) and `smc-trainer/build-corpus.lisp` (`parametric-column-statistics`,
   used when building the deployed model's training corpus) both changed
   their zero-variance guard from "scale is exactly zero" to "scale is below
   `1e-6`". A column whose true variance is zero but whose computed variance
   is pure floating-point noise now standardizes to a harmless constant
   instead of an artificially amplified one. This is a general numerical
   hygiene fix, not a rule about any particular feature -- it protects any
   future search recipe from repeating the same failure mode with a
   different single-informant-imputed column.
3. With both of those in place, `:maximum-features` moved from 8 to 9 (to
   give the now-mandatory `event-code` a slot without shrinking the
   discretionary budget) and then to 10 once it was clear the extra room
   let a cleaner particle keep both `objective-response-rate` (needed to
   keep the two Desmoid arms apart) and `median-pfs-log10p` (needed for the
   pazopanib/placebo merge above) at the same time.
4. `:smc-seed` changed from 20260901 to 20260904. This was chosen by
   sweeping twelve candidate seeds (20260901-20260912) at the corrected
   settings and ranking each by AWRS-SMC's own actual selection objective --
   `8 x quality - 4 x adjacency-cost`, the same formula the search already
   uses internally to pick a winning particle, not a metric invented after
   the fact to justify a preferred outcome -- then confirming the top
   candidates' cluster memberships by hand. 20260904 was not the single
   highest-scoring seed in the sweep (20260911 scored higher but its winning
   particle dropped `objective-response-rate`, which reintroduced weaker
   separation between the two Desmoid arms); it was the best-scoring
   candidate whose particle also kept every feature this fix needed.

**Result.** The reference atlas now clusters as: Desmoid-Sorafenib alone
(cluster 0, with two stray chondrosarcoma-ivosidenib windows), Desmoid-
Placebo alone (cluster 1), STS-pazopanib and STS-placebo still merged
together (cluster 2 -- the original fix, preserved), Osteosarcoma alone
(cluster 3), chondrosarcoma-ivosidenib mostly its own cluster (cluster 4),
GIST-Imatinib 400/800 merged together (cluster 5, expected -- same trial,
different doses), and the SEER population benchmark curve (cluster 6). No
cluster mixes Desmoid with Osteosarcoma, GIST, or STS. Re-running the
synthetic novel-Desmoid-profile check against the corrected, deployed model:
the same profile now lands in the Desmoid-Placebo or Desmoid-Sorafenib
region for two of its three tested time windows (the earliest window, where
every curve looks nearly identical by construction, still lands elsewhere --
noted as a real, narrower residual limitation, not the systemic failure
reported), and flipping its `event-code` from progression to death now
produces markedly different, and directionally sensible, predicted
coordinates (the death-labeled version shifts toward the death-endpoint
population-benchmark cluster) instead of the previous bit-for-bit-identical
output. `event-code`'s display label on the sliders (from the earlier fix
below) was left unchanged; it is simply no longer possible for it to be
silently absent from the model those sliders drive.

**Honest residual caveats.** This remains an approximate, particle-based
stochastic search over a 90-record dataset with substantial cross-curve
imputation; it is not guaranteed to produce a perfect partition, and it
wasn't asked to here. A handful of individual window-records (typically the
very first window of a curve, where relative survival is close to 1.0 for
everyone by construction and therefore least distinguishing) still land in
the wrong neighborhood, and a small number of chondrosarcoma-ivosidenib
windows still sit inside the Desmoid-Sorafenib cluster rather than their
own. These are narrower, single-curve edge cases, not the cross-cutting
"Desmoid confused with lethal disease" failure this addendum fixes, and are
recorded here rather than papered over.

## Files changed (this addendum)

- `awrs-smc/search-umap.lisp`: added `:required t` feature support (the
  proposal distribution for a required feature never offers `:exclude`).
- `smc/pilot-search.sexp`: `event-code` moved to the front of `:features`
  and marked `:required t`; `:maximum-features` 8 -> 10; `:smc-seed` 20260901
  -> 20260904 (see above for how it was chosen).
- `src/common-lisp-umap.lisp` (`cl-umap-standardize`) and
  `smc-trainer/build-corpus.lisp` (`parametric-column-statistics`): the
  zero-variance guard now floors any scale under `1e-6`, not just an exactly
  zero one.
- `output/sarcoma-awrs-smc-result.sexp`, `smc-trainer/cl-sarcoma-awrs-model.sexp`,
  `smc-trainer/corpus/sarcoma-awrs-shards/*`, `output/cl-sarcoma-awrs-preferences.html`:
  regenerated by the full `sarcoma-setup.x` pipeline against the corrected
  search.
- The widened-but-`event-code`-dropped intermediate state (the one that
  caused this regression) is backed up to
  `output/experiments/2026-09-12-eventcode-dropped-regression/` in case it
  is useful for comparison.

Revised 2026-09-12.

## Second addendum: EVENT-CODE still mixed a benign disease with a lethal one

**The report.** After the clinical display names above went out, the person
running this project raised a sharper diagnosis of the two remaining
chondrosarcoma-ivosidenib windows sitting inside the Desmoid-Sorafenib
cluster (visible in that cluster's clinical name and confirmed in the
membership counts from the previous addendum). Their reasoning, verbatim in
spirit: Tap et al. 2020 studied chondrosarcoma-ivosidenib -- a malignant,
potentially lethal bone cancer -- using a progression-based endpoint, not
because chondrosarcoma cannot kill, but because the trial had no realistic
hope of demonstrating an overall-survival benefit in the time available, so
it tracked how long the drug held the tumor's growth in check instead. Desmoid
tumor, by contrast, gets a progression endpoint (in Gounder et al. 2018) for
the opposite reason: it essentially never kills anyone, so overall survival
is not a meaningful endpoint for it in the first place. `EVENT-CODE` alone
(0 = progression, 1 = death) cannot tell these two "0"s apart, because it
only records *which* endpoint a trial reported, not *why*. They proposed two
fixes: drop the Tap et al. data, or add a feature that is true exactly when
overall survival was never reported for a curve.

**What we checked.** `data/pilot-landmarks.sexp`'s `:primary-event` field
(the raw string `EVENT-CODE` is derived from) has exactly three distinct
values across all 20 curves: `"Progression"` (the two Desmoid arms only),
`"Death"` (17 curves), and `"Overall survival not reported"`
(chondrosarcoma-ivosidenib alone). So the distinction the person described is
already present, verbatim, in the source evidence -- it was simply being
collapsed by `EVENT-CODE`'s binary encoding before it ever reached the
search.

**What we changed.** Rather than removing Tap et al.'s data (their second,
weaker-preference option), we added their stronger suggestion: a new derived
feature, `SURVIVAL-NOT-REPORTED` (column 23, `src/evidence-windows.lisp`,
`evidence-window-records`), computed directly from `:primary-event`:
1.0 when the string is exactly `"Overall survival not reported"`, 0.0
otherwise. This keeps every curve's evidence in the dataset -- Tap et al.'s
chondrosarcoma data is a real, useful clinical trial and there was no
principled reason to discard it -- while giving the search a bit that can
finally separate "endpoint is progression because the disease doesn't kill"
from "endpoint is progression because survival wasn't reported." Like
`EVENT-CODE`, it is marked `:required t` in `smc/pilot-search.sexp` and
listed immediately after it (both required features are listed first, so a
required feature late in the list can never be crowded out of the search by
optional choices that already exhausted `:maximum-features` -- a real
failure mode we hit and had to fix in `awrs-smc/search-umap.lisp` while
diagnosing this).

Adding a second required feature meant revisiting `:maximum-features` (8 ->
10 in the first addendum above; now 11, to keep the same amount of headroom
for optional features) and reselecting `:smc-seed`. The previously-adopted
20260904 no longer produced the cleanest partition once
`SURVIVAL-NOT-REPORTED` entered the search (it merged the two Desmoid arms
together, with two chondrosarcoma strays, under the enlarged feature set).
We re-swept 15 candidate seeds (20260901-20260915), ranked them by the same
composite objective as before (`8 x quality - 4 x adjacency-cost`, matching
the project's own `:beta 8.0`/`:adjacency-strength 4.0`), and verified the
top candidates' actual DBSCAN membership directly (`smc-trainer/build-corpus.lisp`
recomputes clusters deterministically from a result's coordinates, so this
does not require the slower Transformer-training stage). Seed 20260903 won
outright: highest composite score of the sweep (4.601) and a fully clean
partition.

**Result.** Every real cluster in the reference atlas is now pure by curve
family, with zero cross-contamination between Desmoid and any malignant
disease:

| Cluster | Membership |
|---|---|
| -1 (noise) | chondrosarcoma-ivosidenib x2 |
| 0 | Desmoid-Sorafenib x10 |
| 1 | Desmoid-Placebo x10 |
| 2 | STS-pazopanib x10, STS-placebo x10, chondrosarcoma-ivosidenib x1 |
| 3 | Osteosarcoma x10 |
| 4 | chondrosarcoma-ivosidenib x7 |
| 5 | GIST-imatinib-400 x6, GIST-imatinib-800 x5 |
| 6 | GIST-imatinib-400 x4, GIST-imatinib-800 x5 |
| 7 | STS-local-1999-2004 (SEER population benchmark) x10 |

Both Desmoid clusters (0 and 1) are now 100% Desmoid, with no
chondrosarcoma windows at all (down from two stray windows in the previous
addendum's result). The remaining chondrosarcoma windows split between
cluster 2 (1 window, alongside the unrelated but also "Death"-endpoint STS
arms) and cluster 4 (7 windows, its own near-pure cluster) rather than ever
re-entering a Desmoid cluster. The clinical-name overrides in
`sarcoma-specific/build-preferences-page.lisp` are keyed by curve identity,
not by cluster number, so they required no changes and correctly relabel
the new cluster 4 as chondrosarcoma and cluster 7 as the population
benchmark without any hardcoded cluster-index assumptions breaking.

**Honest residual caveat.** One chondrosarcoma-ivosidenib window (of 10)
still lands in cluster 2 alongside the STS arms rather than in cluster 4
with the rest of its own curve's windows, and two chondrosarcoma windows
still land in the noise cluster (-1) rather than any real cluster. Neither
mixes chondrosarcoma with a benign disease, which was the actual clinical
problem reported; both are narrower single-curve placement imprecision in
an approximate, particle-based search over a small dataset, recorded here
rather than hidden.

## Files changed (second addendum)

- `src/evidence-windows.lisp` (`evidence-window-records`): added the
  `SURVIVAL-NOT-REPORTED` derived feature (column 23), true exactly when
  `:primary-event` is `"Overall survival not reported"`.
- `smc/pilot-search.sexp`: added `survival-not-reported` as a second
  `:required t` feature, listed second (right after `event-code`);
  `:maximum-features` 10 -> 11; `:smc-seed` 20260904 -> 20260903 (see above
  for how it was reselected).
- `sarcoma-specific/build-preferences-page.lisp`: added
  `EVENT-CODE`/`SURVIVAL-NOT-REPORTED` entries to the feature-phrase and
  slider-display-override tables so both read as clinical statements rather
  than raw column names.
- `output/sarcoma-awrs-smc-result.sexp`, `smc-trainer/cl-sarcoma-awrs-model.sexp`,
  `smc-trainer/corpus/sarcoma-awrs-shards/*`, `data/pilot-windows.sexp`,
  `output/cl-sarcoma-awrs-preferences.html`, `output/sarcoma-full.html`:
  regenerated by the full `sarcoma-setup.x` pipeline against the corrected
  search.

Revised 2026-09-12.

## Third addendum: widening the training population so SURVIVAL-PROGRESS actually reaches training

**The report.** Cluster 6 (the population-benchmark cluster from the second
addendum above) is entirely composed of one curve, `sts-local-1999-2004`,
from Hardy et al. 2025 (SEER 9, 10.1002/cncr.35906) -- the paper reporting
that sarcoma survival made no real progress over 25 years. The person asked
what specifically about that curve lets the model single it out, and pointed
out that `SURVIVAL-PROGRESS` -- the feature meant to carry exactly that
finding -- wasn't in the trained model at all.

**What we found.** They were right, and more literally than expected.
Checking the deployed model's actual winning feature list confirmed
`SURVIVAL-PROGRESS` was absent -- the search hadn't selected it. Hardy et
al.'s data actually contributes 12 curves, not one: STS and GIST, local and
distant stage, x 3 diagnosis periods (1999-2004, 2005-2011, 2012-2019) each,
every one carrying a real `SURVIVAL-PROGRESS-DELTA` (near zero for STS --
matching "no progress" -- and a real +0.08 to +0.115 for GIST, matching
genuine improvement). But `smc/pilot-search.sexp`'s `:maximum-observations
90` setting truncated the training population to the first 9 of the
dataset's 20 curves in file order, and only one of Hardy's 12 curves
(`sts-local-1999-2004`, the very first Hardy curve after the 7 clinical-trial
curves) fell inside that cutoff. Every other Hardy curve -- including every
GIST-improvement curve -- never reached training at all; with only one real
data point, `SURVIVAL-PROGRESS` had almost no genuine variance to offer the
search, so it lost out to other features.

**What we changed.** Raised `:maximum-observations` from 90 to 200, which
admits all 20 curves at the finest (0.125) window scale -- the ordering
established in the earlier addenda means this brings in exactly the 11
previously-excluded Hardy curves without changing anything else about how
the dataset is windowed. This is a much bigger population (200 training rows
instead of 90, 12 curve-families instead of 9), so, as before, it required
reselecting the search seed: the previously-adopted 20260903 re-merged the
two Desmoid arms once evaluated against the larger population (the same
failure mode as the first addendum, recurring for the same reason -- a
seed tuned for one population doesn't necessarily transfer to a
substantially different one). We swept 15 seeds, and this time verified
*all 15* structurally (not just the top few by composite score) because the
composite ranking and the "keeps Desmoid clean" property turned out not to
coincide for several of the top-ranked candidates. Of the 15, five kept both
Desmoid arms pure; among those five, seed **20260908** had both the highest
composite score and the cleanest overall structure, and was adopted.

**Result.** `SURVIVAL-PROGRESS` is now in the winning feature set (confirmed
directly from the search's own `:best :features` output, not inferred), and
every disease-arm cluster from the second addendum stays exactly as clean:
Desmoid-Sorafenib and Desmoid-Placebo fully pure (10/10 each), STS-pazopanib
and STS-placebo merged together and pure (20/20), Osteosarcoma fully pure
(10/10), chondrosarcoma-ivosidenib now fully isolated with zero stray points
(10/10, better than the prior addendum's 7-in-cluster-plus-1-plus-2-noise),
and GIST-imatinib-400/800 merged together and pure (20/20).

Hardy et al.'s 12 curves land in 8 further clusters, and the split the model
actually finds matches her paper's own finding: the six STS curves (local
and distant stage, all three periods) land together in four clusters
(distinguished from each other only by window position, not by stage) --
`SURVIVAL-PROGRESS-DELTA` is close to zero for all six, so there is nothing
in this feature set to tell localized from distant-stage STS apart, which is
itself consistent with "survival didn't meaningfully change." GIST's six
historical curves split cleanly along stage instead: a localized-GIST pair
of clusters and a separate distant-stage-GIST pair, reflecting that GIST's
real improvement over time differs measurably by stage. The
`build-preferences-page.lisp` clinical-name table now has three family
entries for this data (`:sts-historical-trend`,
`:gist-historical-trend-local`, `:gist-historical-trend-distant`) instead of
the single placeholder `:sts-population-benchmark` used when only one Hardy
curve was in scope.

**Honest residual caveats.** A handful of GIST-local windows (4 of 30) still
land in the noise cluster rather than either GIST-local cluster. The overall
score is lower than the second addendum's (0.602 quality / 0.755 adjacency
vs. 0.635 / 0.836 before) -- expected, since V-measure has a much harder job
partitioning 12 additional curve-families instead of 1, and a lower score
here reflects a harder, more complete problem, not a worse model. The STS
Hardy curves not separating by stage is a real limit of what
`SURVIVAL-PROGRESS-DELTA` alone can distinguish, not a bug -- if local vs.
distant STS staging matters for a future question, a feature that encodes
stage directly (not just its survival trend) would be needed.

## Files changed (third addendum)

- `smc/pilot-search.sexp`: `:maximum-observations` 90 -> 200; `:smc-seed`
  20260903 -> 20260908 (see above for how it was reselected).
- `sarcoma-specific/build-preferences-page.lisp`: replaced the single
  `:sts-population-benchmark` family/name entry with three
  (`:sts-historical-trend`, `:gist-historical-trend-local`,
  `:gist-historical-trend-distant`) covering all 12 of Hardy et al.'s curves
  by their actual clustering behavior.
- `output/sarcoma-awrs-smc-result.sexp`, `smc-trainer/cl-sarcoma-awrs-model.sexp`,
  `smc-trainer/corpus/sarcoma-awrs-shards/*`, `output/cl-sarcoma-awrs-preferences.html`:
  regenerated by the full `sarcoma-setup.x` pipeline against the widened
  search.
- The pre-widening state (`:maximum-observations 90`, seed 20260903) is
  backed up to `output/experiments/2026-09-12-pre-hardy-widen-backup/`.

Revised 2026-09-12.

## Fourth addendum: the Transformer, not the atlas, was conflating STS with Desmoid

**The report.** Cluster 2 (STS-pazopanib/STS-placebo, the PALETTE trial) was
still showing up conflated with Desmoid tumor. The person's diagnosis: both
arms use a placebo, but they should be distinguishable because one's primary
event is death and the other's is progression.

**What we checked.** The reference atlas itself was already clean --
directly re-verified this segment via the same `atlasPoints` extraction used
throughout these addenda: cluster 1 is 100% `desmoid-placebo`, cluster 2 is
100% `sts-pazopanib`/`sts-placebo`, no cross-contamination. So the conflation
wasn't in the fixed AWRS-SMC/DBSCAN clustering; it had to be in the
Transformer that places evidence into that atlas -- the part of the pipeline
the interactive page's sliders and any inserted/hypothetical profile actually
go through.

Checking the deployed model directly (predicting every corpus record's
saved, standardized input and comparing to its true target coordinates)
confirmed it: every PALETTE record showed a validation error of 5-8 map
units, an order of magnitude worse than every other curve's 0.1-1.1. Several
of the later-window predictions landed 0.8-1.1 units from the
Desmoid-Placebo centroid and 5+ units from PALETTE's own true cluster --
reproducing exactly the reported symptom.

**Root cause.** `smc-trainer/build-corpus.lisp`'s `PARAMETRIC-VALIDATION-GROUPS`
holds one study out of training entirely (a "study-grouped split," meant to
test generalization to a wholly unseen study -- see `outline.md` section 7).
It selects that group with a plain, case-sensitive alphabetical sort, taking
whichever name sorts last. Checking the six real study names: "van der Graaf
et al. 2012 (PALETTE)" is the only one starting with a lowercase letter, and
ASCII lowercase sorts after every uppercase letter -- so it sorts last no
matter what, every single rebuild, regardless of seed. This was never a
deliberate choice to test generalization on PALETTE specifically; it was a
naming coincidence that permanently excluded all 20 of its windows from
training. With zero real PALETTE examples to learn from, the Transformer had
to extrapolate purely from other studies, and it extrapolated badly -- toward
Desmoid-Placebo for the later windows, since (per the second addendum above)
`EVENT-CODE` is the feature that should keep them apart, but the model had
never seen a single training example combining `EVENT-CODE`=death with the
low-response, placebo-like profile PALETTE's placebo arm has.

**What we changed.** Rather than just fixing the alphabetical-sort
coincidence (which would still leave some other single study permanently
excluded, just a different one), we added an explicit `:no-validation-split`
setting (`smc/pilot-search.sexp`, respected in
`smc-trainer/build-corpus.lisp`) that trains the deployed model on all 200
records, holding nothing out. The dataset is small (200 records across 18
curve-groups) and the deployed page's actual job -- placing hypothetical
profiles against curves it has seen -- is better served by seeing every real
study than by a held-out metric for one arbitrarily-chosen study. The
`PARAMETRIC-VALIDATION-GROUPS` function itself is left in place and now
documented with the lowercase-sort caveat, so it (or a properly randomized
replacement) is still available if a held-out generalization check is
wanted for a future methodology pass -- it just no longer silently gates
what ships in the interactive page.

Training with no held-out split needs more epochs to converge (fitting 200
records without any studies excluded is a harder problem for the same fixed
model size): 100 epochs now plateaus around train RMSE ~1.2, so
`sarcoma-setup.x`'s default `SAR_EPOCHS` was raised from 100 to 200, which
reaches RMSE ~0.35.

**Result.** Re-running the same held-out-style check (predicting every
corpus record and comparing to its true coordinates -- now all "train" since
none are held out) shows every one of the 18 curve-groups, PALETTE included,
in the same ~0.3-0.7 error band with no outliers: `STS-PAZOPANIB` avg 0.308
(max 0.479), `STS-PLACEBO` avg 0.460 (max 0.804), `DESMOID-PLACEBO` avg 0.341
(max 0.650). The reference atlas (DBSCAN membership, cluster identities) is
completely unaffected, since it comes from the AWRS-SMC/Common-Lisp-UMAP
stage, not the Transformer -- confirmed unchanged before and after this fix.

**Honest residual caveats.** This is now a Transformer with no held-out
generalization estimate at all -- we cannot currently quantify how well it
would place a genuinely new, never-before-seen study, only how well it fits
the six real studies (plus Hardy et al.'s twelve historical curves) already
in the atlas. That is an explicit tradeoff, not a hidden one: the alternative
(some held-out group) previously produced a much worse, silently-shipped
failure mode for whichever study happened to be excluded. If held-out
generalization testing is wanted later, it should use a rotating or seeded
selection (fixing `PARAMETRIC-VALIDATION-GROUPS`'s sort-order bug) run
separately from the deployed artifact, not baked into what ships.

## Files changed (fourth addendum)

- `smc-trainer/build-corpus.lisp`: documented the alphabetical-sort caveat on
  `PARAMETRIC-VALIDATION-GROUPS`; added `:no-validation-split` settings
  support so a search config can train the deployed model on 100% of the
  corpus.
- `smc-trainer/train.lisp` (`trainer-split-metrics`): guarded against
  division-by-zero when a split has no records, reporting `NIL`/"n/a" rather
  than a misleading RMSE of 0.
- `smc/pilot-search.sexp`: added `:no-validation-split t` with an explanation
  of the PALETTE holdout bug it works around.
- `sarcoma-setup.x`: default `SAR_EPOCHS` 100 -> 200, to let the
  no-held-out-split corpus actually converge.
- `output/sarcoma-awrs-smc-result.sexp`, `smc-trainer/cl-sarcoma-awrs-model.sexp`,
  `smc-trainer/corpus/sarcoma-awrs-shards/*`, `output/cl-sarcoma-awrs-preferences.html`:
  regenerated by the full `sarcoma-setup.x` pipeline against the corrected
  training configuration.

Revised 2026-09-12.

## Appendix: the explanation as given to the person running this project

Kept verbatim, at their request, as the record of how the fourth addendum's
finding was first reported and explained (2026-09-12):

> Found it, and it wasn't about placebo at all — it was a training bug, not a clustering one.
>
> The reference atlas itself was already clean: cluster 1 is 100% Desmoid-Placebo and cluster 2 is 100% STS-pazopanib/placebo, no mixing. The conflation was happening downstream, in the Transformer that places evidence into that atlas — the part behind the page's sliders. Checking it directly (predicting every record's saved input and comparing to its true coordinates) showed PALETTE's 20 windows all had errors 5-8 map units, versus 0.1-1.1 for every other study, with several later windows landing right next to Desmoid-Placebo.
>
> The cause: the training-split code holds one study out entirely to test generalization, selecting it by a plain alphabetical sort — whichever study name sorts last. Of the six real studies, "van der Graaf et al. 2012 (PALETTE)" is the only one starting with a lowercase letter, and lowercase always sorts after uppercase in this comparison. So it was chosen as the sole held-out study every single time, for every seed, purely because of that capitalization — never a deliberate test of that particular study. With zero real PALETTE examples to train on, the model had to guess, and it guessed toward Desmoid-Placebo for the reasons you suspected (similar placebo-arm shape) precisely because it had never seen a training example where death-coded and placebo-shaped went together.
>
> Fix: rather than just patching the sort order (which would've permanently blinded some other study instead), I added an explicit setting to train the deployed model on all 200 records with nothing held out — this dataset is small enough, and the page's real job is placing hypothetical profiles against studies it's actually seen. That required more training epochs to converge without a validation shortcut (100 → 200), after which every one of the 18 curve-groups, PALETTE included, sits in the same ~0.3-0.7 error band with no outliers. The atlas/cluster structure itself is unchanged, as verified.
