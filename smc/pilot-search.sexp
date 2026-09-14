(:format :umap-smc-search
 :version 1
 :manifest "../pilot-problem.sexp"
 :label-field :sarcoma-type
 :search (:particles 64 :beam-factor 4
          :minimum-features 2 :maximum-features 11
          :beta 8.0d0 :feature-penalty 0.002d0
          :adjacency-strength 4.0d0 :resampling-threshold 0.25d0
          :maximum-observations 200
          :neighbors 20 :minimum-distance 0.4d0 :epochs 35
          :standardize t :minimum-points 5 :epsilon :automatic
          :umap-seed 20260831 :smc-seed  20260908
          :no-validation-split t)
 ;; :NO-VALIDATION-SPLIT T (see smc-trainer/build-corpus.lisp) trains the
 ;; deployed Transformer on every one of the 200 rows, with no study held
 ;; out. Without it, PARAMETRIC-VALIDATION-GROUPS' plain alphabetical sort
 ;; always picks "van der Graaf et al. 2012 (PALETTE)" -- the STS-pazopanib/
 ;; STS-placebo study -- as the sole validation group, forever, purely
 ;; because its name starts with a lowercase "v" (ASCII lowercase sorts after
 ;; every uppercase-initial study name here). That is not a deliberate choice
 ;; to test generalization on that study; it is a naming coincidence that
 ;; permanently hid all 20 PALETTE windows from training. The predicted
 ;; placements this produced were badly wrong (validation RMSE ~5-8 vs.
 ;; ~0.1-1 for trained studies) and several windows landed within ~1 unit of
 ;; the Desmoid-Placebo cluster instead of near PALETTE's own cluster --
 ;; exactly the "STS conflated with Desmoid" symptom reported and diagnosed
 ;; in PAZOPANIB-PLACEBO-CLUSTER-MERGE.md's fourth addendum. This dataset is
 ;; small enough, and the deployed page's job (placing hypothetical profiles
 ;; against curves it has actually seen) important enough, that shipping a
 ;; model blind to one entire real study is worse than not holding one out.
 ;;
 ;; :MAXIMUM-OBSERVATIONS was 90 (the first 9 of the 20 evidence curves, at
 ;; the finest 0.125 window scale -- see data/pilot-landmarks.sexp for curve
 ;; order). That silently excluded 11 of Hardy et al. 2025's 12 SEER
 ;; population-trend curves from training: only STS-LOCAL-1999-2004 (the
 ;; very first Hardy curve in file order) was ever seen, so SURVIVAL-PROGRESS
 ;; (the feature meant to carry Hardy's "no progress in 25 years for STS/bone
 ;; sarcoma, but real progress for GIST" finding) had almost no real variance
 ;; to offer the search and was not selected. 200 admits all 20 curves at the
 ;; 0.125 window scale (20 curves x 10 windows = 200 rows), so every one of
 ;; Hardy's curves -- including the GIST-local/distant windows that carry the
 ;; real +0.08/+0.115 improvement signal, not just the near-zero STS windows
 ;; -- now reaches training.
 ;;
 ;; EVENT-CODE and SURVIVAL-NOT-REPORTED are listed first and marked
 ;; :required t so AWRS-SMC's proposal step never offers :exclude for
 ;; either (see awrs-smc/search-umap.lisp). EVENT-CODE is the primary-event
 ;; endpoint (0 = progression, 1 = death); SURVIVAL-NOT-REPORTED (column 23,
 ;; src/evidence-windows.lisp) breaks the one case EVENT-CODE alone
 ;; conflates: a disease whose natural history genuinely ends in
 ;; progression rather than death (Desmoid tumor, EVENT-CODE 0) versus a
 ;; malignant disease whose trial simply never reported an overall-survival
 ;; endpoint (chondrosarcoma-ivosidenib / Tap et al. 2020, also EVENT-CODE 0
 ;; despite being a life-threatening cancer). Without it, a stochastic
 ;; search has no way to keep those two apart, which is what let a handful
 ;; of chondrosarcoma-ivosidenib windows land inside the Desmoid cluster.
 ;; Both are first in the list, not just :required, so that a required
 ;; feature later in the list can never be crowded out by earlier optional
 ;; choices already having exhausted :maximum-features (which surfaces as
 ;; "no proposal mass remains after rejections").
 :features
 ((:name :event-code :column 22 :required t
   :transformations (:identity))
  (:name :survival-not-reported :column 23 :required t
   :transformations (:identity))
  (:name :survival-now :column 0
   :transformations (:identity :protected-logit))
  (:name :survival-next :column 1
   :transformations (:identity :protected-logit))
  (:name :local-drop :column 5
   :transformations (:identity :protected-logit))
  (:name :window-area :column 6
   :transformations (:identity :protected-logit))
  (:name :window-start-fraction :column 7
   :transformations (:identity :protected-logit))
  (:name :maximum-months-log10p :column 8
   :transformations (:identity))
  (:name :cohort-size-log10p :column 9
   :transformations (:identity))
  (:name :median-pfs-log10p :column 10
   :transformations (:identity))
  (:name :median-os-log10p :column 11
   :transformations (:identity))
  (:name :follow-up-log10p :column 12
   :transformations (:identity))
  (:name :objective-response-rate :column 13
   :transformations (:identity :protected-logit))
  (:name :disease-control-rate :column 14
   :transformations (:identity :protected-logit))
  (:name :survival-progress :column 18
   :transformations (:identity :signed-log1p :asinh))
  (:name :overall-survival-36 :column 19
   :transformations (:identity :protected-logit))
  (:name :overall-survival-60 :column 20
   :transformations (:identity :protected-logit))
  (:name :overall-survival-120 :column 21
   :transformations (:identity :protected-logit))))
