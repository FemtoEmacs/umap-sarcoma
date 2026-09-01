(:format :umap-smc-search
 :version 1
 :manifest "../pilot-problem.sexp"
 :label-field :sarcoma-type
 :search (:particles 4 :beam-factor 3
          :minimum-features 2 :maximum-features 6
          :beta 8.0d0 :feature-penalty 0.002d0
          :maximum-observations 90
          :neighbors 20 :minimum-distance 0.4d0 :epochs 35
          :standardize t :minimum-points 5 :epsilon :automatic
          :umap-seed 20260831 :smc-seed 20260901)
 :features
 ((:name :survival-now :column 0
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
   :transformations (:identity :protected-logit))
  (:name :event-code :column 22
   :transformations (:identity))))
