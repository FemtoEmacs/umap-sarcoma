# Pilot sarcoma evidence UMAP

This first implementation tests whether heterogeneous published evidence
profiles produce useful local neighborhoods. It includes twenty study arms or
reported stage-and-era strata from
four sarcoma types: desmoid tumor, soft-tissue sarcoma, bone sarcoma, and GIST.
Osteosarcoma and chondrosarcoma remain separate histologies within bone sarcoma.

The 23-dimensional vectors combine the disease-appropriate event curve, median PFS and OS, OS
landmarks, objective response, disease control, time to response, PFS and OS
hazard ratios, follow-up, and cohort size when reported. All nonnegative
survival-shape coordinates remain on their raw 0--1 probability scale. Other
nonnegative quantities receive `log10(1+x)`. The signed survival-progress
dimension records change in five-year OS across calendar eras when reported.
Optional values are median-imputed solely for
the embedding geometry; their reporting status remains in the audit record and
is deliberately excluded from distance calculations. Disease, therapy,
histology, study, DOI, and acquisition type are metadata and do not determine
the embedding.

The primary-event dimension distinguishes progression (`0`) from death (`1`).
Desmoid tumor uses progression-free survival because death is uncommon. Soft-
tissue sarcoma, osteosarcoma, and GIST use overall survival when reported. The
current chondrosarcoma source reports PFS but not OS; it is labeled accordingly
rather than being silently treated as death evidence.

Build from the repository root:

```sh
sbcl --script prepare-umap-data.lisp pilot-problem.sexp
sbcl --script build-umap.lisp pilot-problem.sexp index.html
sbcl --script tests/evidence-umap-tests.lisp
```

Open `index.html` in a current browser with Internet access. Hovering a point
shows its study metadata and miniature time-to-event curve. Ten temporal
anchors at short, medium, and long window scales provide local neighborhoods for a
connected pilot manifold while mixed outcome dimensions prevent curve shape
from being the only signal. These profiles are not independent
observations, so the pilot is a visualization and software test rather than a
quantitative pooled meta-analysis.

The pilot deliberately uses a large 300-neighbor graph. With only twenty study
arms, a small local graph represents arms as isolated islands and merely
recapitulates study identity. The larger graph tests the stated hypothesis of
a shared sarcoma evidence continuum; that connectedness is therefore a design
assumption to be reassessed as more independent studies are added.
