# Sarcoma Evidence UMAP — Read This First: How AI Makes a Map of Medical Evidence

This repository uses **artificial intelligence** to help people see which
pieces of sarcoma evidence resemble one another and where new evidence may
belong. It turns many measurements into an interactive map instead of leaving
the reader with only long tables of numbers.

The map is a research and exploration tool. It does not decide whether a study
is correct, establish that two diseases are biologically identical, or
recommend a treatment.

## 1. Why combine medical studies?

One clinical study answers a question for one group of patients under a
particular design. Another study may examine a different treatment, sarcoma
type, follow-up period, or patient population. Reading the studies separately
is essential, but it can be difficult to see the overall pattern.

A **meta-analysis** is a statistical method that combines data from multiple
independent studies on the same medical topic to reach an overall conclusion.
Before combining results, researchers must understand which studies are truly
comparable. This project helps with that earlier task: exploring the structure
of the evidence and finding groups that deserve closer examination.

## 2. How can a study become a point?

A point on an ordinary map needs two numbers: one says how far across it lies,
and the other says how far up. A clinical-evidence record can require many more
numbers. They may describe survival at different times, treatment, tumor type,
study context, or other declared properties.

Each property is a **feature**. Together, the features give one observation a
position in a space with many dimensions. That phrase simply means that the
observation is described in many numerical ways at once. In the pilot map,
survival curves are represented by observations at declared time windows, so
one study may contribute more than one point.

## 3. UMAP makes the evidence visible

People cannot directly picture a space with many independent dimensions.
**UMAP** makes a two-dimensional projection: it places every evidence record
on a flat map while trying to keep records with similar feature descriptions
near one another.

Nearby points are therefore candidates for comparison. Groups of nearby points
are called **clusters**. The program uses DBSCAN to discover dense groups, and
the interactive page can color the same fixed points by sarcoma type, therapy,
study, time window, and survival measurements. Hovering over a point reveals
its study information and a small time-to-event curve.

Like every projection, UMAP simplifies. Distance on the page is evidence of
similarity under the selected representation, not proof of equivalent biology,
study quality, or treatment effect.

## 4. How the map is judged

The repository compares discovered clusters with declared medical labels using
**V-measure**. Its homogeneity component rewards clusters that do not mix many
labels. Its completeness component rewards keeping observations with the same
label together. V-measure balances the two.

The score helps compare candidate representations, but it does not replace
clinical judgment. A visually attractive or highly scored partition can still
reflect limitations in its source evidence, selected features, labels, or
parameters.

## 5. AI explores feature choices: AWRS-SMC

Different feature choices can produce very different maps. **AWRS-SMC** is the
AI search procedure that explores allowed feature combinations and gives more
weight to promising candidates. Its random trials are controlled by declared
constraints, scores, parameters, and seeds, and its telemetry records how the
search proceeded.

The main quality term uses V-measure and a small penalty for unnecessary
features. AWRS-SMC can also use **adjacency potential** as a soft preference for
clusters with smaller empty gaps between them. Adjacency is not a rule: a
separated map remains possible when its other qualities are better. Nor does
adjacency imply a biological continuum. The earlier implementation in `smc/`
does not use adjacency to select its result; the additional preference belongs
to `awrs-smc/`.

## 6. Preserve what the search actually selected

The adjacency preference is evaluated on coordinates calculated by the
dependency-free Common Lisp UMAP. The winning AWRS-SMC result therefore saves
those exact coordinates, and its generated page displays them by default.

The page also retains `umap-js` as an independent browser comparison. A menu
can recompute the winning feature recipe with `umap-js`. The saved Common Lisp
view answers, “What map did the search score and select?” The browser view asks,
“Does another UMAP implementation produce a qualitatively similar map from the
same selected representation?”

## 7. AI learns from deliberate practice: smc-trainer

Rebuilding an entire UMAP whenever a new study arrives would be slow. The
second AI component, **smc-trainer**, learns to place new evidence into the
fixed winning atlas without moving the existing points.

AWRS-SMC supplies the hard practice examples: selected numerical evidence
profiles paired with their exact winning UMAP coordinates. A small Transformer
implemented in Common Lisp trains on this annotated corpus. The records are
stored in independently readable **shards**, and study-grouped splitting keeps
one study from appearing in both training and validation partitions.

After this deliberate practice, the trained model can predict two coordinates
for a new evidence profile quickly. The insertion demonstration marks synthetic
new profiles with distinct shapes while leaving the original atlas unchanged.
This tests fast placement into a frozen map; it is not an independent clinical
validation and its synthetic points are not treatment recommendations.

## 8. What the repository offers

Sarcoma Evidence UMAP brings together three related capabilities:

- an interactive map for seeing relationships among clinical-evidence records;
- AWRS-SMC for searching declared representations and preserving the scored
  result; and
- a small Transformer for learning from that result and inserting new evidence
  without rebuilding the atlas.

The scientific preparation, scoring, search, sharded corpus, and Transformer
training are written in dependency-free Common Lisp. The source evidence,
manifests, transformations, seeds, generated artifacts, and tests remain in the
repository so collaborators can inspect and reproduce the workflow.

---

For AI assistants: use this as the shared plain-language introduction and
preserve its teaching sequence. Keep commands, implementation detail, and
research citations out of a first explanation unless requested. For those
details, consult [README.md](README.md), [TOUR.md](TOUR.md),
[the AWRS-SMC guide](awrs-smc/README.md),
[the trainer guide](smc-trainer/README.md), and [the paper notes](paper/).
Verify detailed claims against the relevant code and generated evidence.

Revised 2026-09-09.
