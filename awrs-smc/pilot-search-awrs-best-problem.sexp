(:FORMAT :UMAP-PROBLEM :VERSION 1 :TITLE
 "Pilot UMAP of sarcoma evidence statistics — best SMC feature set"
 :PREPARATION NIL :DATA
 (:FILE "pilot-search-awrs-best-data.sexp" :RECORDS-KEY :RECORDS :ID-FIELD :ID
  :EMBEDDING ((:FIELD :VECTOR)) :VALIDATION
  (:REQUIRED-FIELDS (:ID :VECTOR :CURVE :SARCOMA-TYPE :THERAPY) :UNIQUE-FIELDS
   (:ID)))
 :PREPROCESSING (:STANDARDIZE TRUE) :UMAP
 (:NEIGHBORS 20 :MINIMUM-DISTANCE 0.4d0 :EPOCHS 35 :SEED 20260831
  :COORDINATE-MODE :PRESERVED :DENSITY-SURFACE T :DENSITY-BANDWIDTH 45
  :DENSITY-THRESHOLDS 10 :DENSITY-OPACITY 0.18d0 :DENSITY-COLOR "data"
  :DENSITY-COLOR-BANDS 7 :POINT-RADIUS 6)
 :SCORING
 (:LABEL-FIELD :SARCOMA-TYPE :BETA 1.0 :OUTPUT
  "output/pilot-problem-score.sexp" :CLUSTERING
  (:ALGORITHM :DBSCAN :MINIMUM-POINTS 5 :EPSILON :AUTOMATIC))
 :VIEWS
 ((:FIELD :SARCOMA-TYPE :LABEL "Sarcoma type" :TYPE "categorical")
  (:FIELD :WINDOW-SCALE :LABEL "Window scale" :TYPE "categorical")
  (:FIELD :THERAPY :LABEL "Therapy" :TYPE "categorical")
  (:FIELD :HISTOLOGY :LABEL "Histology" :TYPE "categorical")
  (:FIELD :STUDY :LABEL "Study" :TYPE "categorical")
  (:FIELD :WINDOW-SURVIVAL :LABEL "Survival at window start" :TYPE
   "continuous")
  (:FIELD :LOCAL-DROP :LABEL "Local survival decline" :TYPE "continuous"))
 :TOOLTIP
 ((:FIELD :STUDY :LABEL "Study") (:FIELD :SARCOMA-TYPE :LABEL "Sarcoma type")
  (:FIELD :THERAPY :LABEL "Therapy" :OMIT-PREFIX "Population survival")
  (:FIELD :ENDPOINT :LABEL "Endpoint")
  (:FIELD :PRIMARY-EVENT :LABEL "Primary event")
  (:FIELD :WINDOW-SCALE :LABEL "Window scale")
  (:FIELD :COHORT-SIZE :LABEL "Cohort")
  (:FIELD :WINDOW-START-MONTHS :LABEL "Window start (months)")
  (:FIELD :WINDOW-END-MONTHS :LABEL "Window end (months)"))
 :TOOLTIP-PLOT
 (:KIND "kaplan-meier" :FIELD :CURVE :X-LABEL "Months" :Y-LABEL
  "Event-free proportion"))
