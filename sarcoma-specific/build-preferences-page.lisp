;;;; Sarcoma page: preserve complete evidence records and train-time transforms.
(defparameter *sarcoma-directory* (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *sarcoma-root* (merge-pathnames "../" *sarcoma-directory*))
(defparameter *build-umap-run-main* nil)
(load (merge-pathnames "build-umap.lisp" *sarcoma-root*))
(defparameter *parametric-predict-run-main* nil)
(load (merge-pathnames "smc-trainer/predict.lisp" *sarcoma-root*))
(load (merge-pathnames "smc-trainer/shards.lisp" *sarcoma-root*))
(defun preferences-model-json-plist (model)
  "Export every parameter tensor MODEL needs for inference, under explicit
names a JavaScript port can look up directly -- deliberately not the
positional :PARAMETERS list transformer.lisp uses for its own serialization,
so the browser-side port does not depend on group ordering."
  (ecase (parametric-model-kind model)
    (:multi-head-stack
     (list :kind "multi-head-stack"
           :d-model (parametric-model-d-model model)
           :d-ff (parametric-model-d-ff model)
           :num-heads (parametric-model-num-heads model)
           :num-layers (parametric-model-num-layers model)
           :feature-count (parametric-model-feature-count model)
           :feature-embeddings (trainer-values (parametric-model-feature-embeddings model))
           :scalar-weights (trainer-values (parametric-model-scalar-weights model))
           :scalar-bias (trainer-values (parametric-model-scalar-bias model))
           :layer-heads-wq (trainer-values (parametric-model-layer-heads-wq model))
           :layer-heads-wk (trainer-values (parametric-model-layer-heads-wk model))
           :layer-heads-wv (trainer-values (parametric-model-layer-heads-wv model))
           :layer-wo (trainer-values (parametric-model-layer-wo model))
           :layer-attention-gain (trainer-values (parametric-model-layer-attention-gain model))
           :layer-w1 (trainer-values (parametric-model-layer-w1 model))
           :layer-b1 (trainer-values (parametric-model-layer-b1 model))
           :layer-w2 (trainer-values (parametric-model-layer-w2 model))
           :layer-b2 (trainer-values (parametric-model-layer-b2 model))
           :layer-ffn-gain (trainer-values (parametric-model-layer-ffn-gain model))
           :final-norm-gain (trainer-values (parametric-model-final-norm-gain model))
           :output-weights (trainer-values (parametric-model-output-weights model))
           :output-bias (trainer-values (parametric-model-output-bias model))))
    (:legacy-single-head
     (list :kind "legacy-single-head"
           :d-model (parametric-model-d-model model)
           :d-ff (parametric-model-d-ff model)
           :feature-count (parametric-model-feature-count model)
           :feature-embeddings (trainer-values (parametric-model-feature-embeddings model))
           :scalar-weights (trainer-values (parametric-model-scalar-weights model))
           :scalar-bias (trainer-values (parametric-model-scalar-bias model))
           :wq (trainer-values (parametric-model-wq model))
           :wk (trainer-values (parametric-model-wk model))
           :wv (trainer-values (parametric-model-wv model))
           :wo (trainer-values (parametric-model-wo model))
           :w1 (trainer-values (parametric-model-w1 model))
           :b1 (trainer-values (parametric-model-b1 model))
           :w2 (trainer-values (parametric-model-w2 model))
           :b2 (trainer-values (parametric-model-b2 model))
           :output-weights (trainer-values (parametric-model-output-weights model))
           :output-bias (trainer-values (parametric-model-output-bias model))))))


(defparameter *sarcoma-feature-phrases*
  ;; (SCHEMA-NAME POSITIVE-PHRASE NEGATIVE-PHRASE), one entry per feature this
  ;; project's search files may declare (smc/pilot-search.sexp and any
  ;; sibling search config) -- see src/evidence-windows.lisp for exactly what
  ;; each column measures. Kept for every declared feature, not just the
  ;; ones the current winning particle selects, so this table doesn't need
  ;; editing if a future search picks a different subset.
  '(("SURVIVAL-NOW" "higher survival at window start" "lower survival at window start")
    ("SURVIVAL-NEXT" "higher survival later in the window" "lower survival later in the window")
    ("LOCAL-DROP" "steeper survival decline within the window" "flatter survival decline within the window")
    ("WINDOW-AREA" "more sustained survival across the window" "less sustained survival across the window")
    ("WINDOW-START-FRACTION" "window starts later in follow-up" "window starts earlier in follow-up")
    ("MAXIMUM-MONTHS-LOG10P" "longer total follow-up horizon" "shorter total follow-up horizon")
    ("COHORT-SIZE-LOG10P" "larger reported cohort" "smaller reported cohort")
    ("MEDIAN-PFS-LOG10P" "longer median progression-free survival" "shorter median progression-free survival")
    ("MEDIAN-OS-LOG10P" "longer median overall survival" "shorter median overall survival")
    ("FOLLOW-UP-LOG10P" "longer reported follow-up" "shorter reported follow-up")
    ("OBJECTIVE-RESPONSE-RATE" "higher objective response rate" "lower objective response rate")
    ("DISEASE-CONTROL-RATE" "higher disease control rate" "lower disease control rate")
    ("SURVIVAL-PROGRESS" "ahead of the historical benchmark" "behind the historical benchmark")
    ("OVERALL-SURVIVAL-36" "higher overall survival at 36 months" "lower overall survival at 36 months")
    ("OVERALL-SURVIVAL-60" "higher overall survival at 60 months" "lower overall survival at 60 months")
    ("OVERALL-SURVIVAL-120" "higher overall survival at 120 months" "lower overall survival at 120 months")
    ("EVENT-CODE" "overall-survival-based endpoint" "progression-based endpoint")
    ("SURVIVAL-NOT-REPORTED" "overall survival not reported by this trial" "overall survival reported by this trial")))

(defun sarcoma-cluster-ranked-phrases (schema profile)
  "All qualifying feature phrases for one cluster's PROFILE (mean z-value
per feature, SCHEMA order), most-defining first -- |mean z| > 0.20, the
same threshold the specialty-umap project's reference-map builder uses --
not just the two used for the short display name, so a name can be
extended with the next feature when two clusters would otherwise collide
on the same short name (see SARCOMA-DISAMBIGUATE-NAMES)."
  (let ((ranked (sort (loop for declared in schema for value in profile
                           collect (list (string (getf declared :name)) value (abs value)))
                      #'> :key #'third)))
    (loop for (name value magnitude) in ranked
          when (> magnitude 0.20d0)
          collect (let ((labels (assoc name *sarcoma-feature-phrases* :test #'string=)))
                    (if labels (if (plusp value) (second labels) (third labels)) name)))))

(defun sarcoma-name-from-phrases (phrases count)
  (format nil "~{~A~^ + ~}" (or (subseq phrases 0 (min count (length phrases)))
                                '("mixed profile"))))

(defun sarcoma-disambiguate-names (entries)
  "ENTRIES: an alist of (cluster-id . ranked-phrases) for the real
(non-noise) clusters, as returned by SARCOMA-CLUSTER-RANKED-PHRASES. This
project's feature set is small (six features in the current search) and a
couple of features can sit near-constant across most clusters, so the
plain top-two name can land on the exact same two phrases for more than
one cluster even though their full ranked lists differ further down.
Starts every cluster at a 2-phrase name and, whenever two or more clusters
would collide on the same name, extends just those clusters one phrase at
a time -- in each cluster's own ranked order -- until the names stop
colliding or a cluster runs out of qualifying phrases to add. Returns an
alist cluster-id -> final display name."
  (let ((counts (make-hash-table :test #'eql)))
    (dolist (entry entries) (setf (gethash (car entry) counts) 2))
    (loop
      (let ((names (mapcar (lambda (entry)
                             (cons (car entry)
                                   (sarcoma-name-from-phrases (cdr entry) (gethash (car entry) counts))))
                           entries))
            (groups (make-hash-table :test #'equal))
            (changed nil))
        (dolist (pair names) (push (car pair) (gethash (cdr pair) groups)))
        (maphash (lambda (name colliding-ids)
                   (declare (ignore name))
                   (when (> (length colliding-ids) 1)
                     (dolist (id colliding-ids)
                       (let ((phrases (cdr (assoc id entries))))
                         (when (< (gethash id counts) (length phrases))
                           (incf (gethash id counts))
                           (setf changed t))))))
                 groups)
        (unless changed
          (return (mapcar (lambda (entry)
                            (cons (car entry)
                                  (sarcoma-name-from-phrases (cdr entry) (gethash (car entry) counts))))
                          entries)))))))

(defparameter *sarcoma-feature-display-overrides*
  ;; (SCHEMA-NAME LABEL UNIT DECIMALS) for every feature this project's
  ;; search files may declare (see src/evidence-windows.lisp for exactly
  ;; what each column measures), so a slider's meaning doesn't depend on
  ;; which subset AWRS-SMC happens to select. Kept for every declared
  ;; feature, not just the ones the current winning particle uses.
  ;; EVENT-CODE is the sharpest case: a categorical 0/1 flag
  ;; (data/pilot-landmarks.sexp -- :event-code 0 when :primary-event is
  ;; "Progression", 1 when it is "Death"), not a continuous measurement.
  ;; The LOG10P features are log10(1 + raw value) -- as the page's own
  ;; intro paragraph already discloses -- so their labels say what the
  ;; underlying raw quantity is, not that the slider itself reads in raw
  ;; units.
  '(("SURVIVAL-NOW" "Relative survival at window start (fraction of the window's starting cohort)" "" 4)
    ("SURVIVAL-NEXT" "Relative survival later in the window (fraction of the window's starting cohort)" "" 4)
    ("LOCAL-DROP" "Proportional survival decline within the window (log10(1+x))" "" 4)
    ("WINDOW-AREA" "Area under the survival curve within the window (log10(1+x))" "" 4)
    ("WINDOW-START-FRACTION" "Window start, as a fraction of total follow-up (log10(1+x))" "" 4)
    ("MAXIMUM-MONTHS-LOG10P" "Total follow-up horizon, months (log10(1+x))" "" 4)
    ("COHORT-SIZE-LOG10P" "Cohort size, patients (log10(1+x))" "" 4)
    ("MEDIAN-PFS-LOG10P" "Median progression-free survival, months (log10(1+x))" "" 4)
    ("MEDIAN-OS-LOG10P" "Median overall survival, months (log10(1+x))" "" 4)
    ("FOLLOW-UP-LOG10P" "Reported follow-up, months (log10(1+x))" "" 4)
    ("OBJECTIVE-RESPONSE-RATE" "Objective response rate (proportion)" "" 4)
    ("DISEASE-CONTROL-RATE" "Disease control rate (proportion)" "" 4)
    ("SURVIVAL-PROGRESS" "Progress vs. the historical benchmark (Hardy et al. 2025)" "" 4)
    ("OVERALL-SURVIVAL-36" "Overall survival probability at 36 months (log10(1+x))" "" 4)
    ("OVERALL-SURVIVAL-60" "Overall survival probability at 60 months (log10(1+x))" "" 4)
    ("OVERALL-SURVIVAL-120" "Overall survival probability at 120 months (log10(1+x))" "" 4)
    ("EVENT-CODE" "Event type (0 = progression, 1 = death)" "" 0)
    ("SURVIVAL-NOT-REPORTED" "This trial did not report an overall-survival endpoint (0 = reported, 1 = not reported)" "" 0)))

(defparameter *sarcoma-curve-family*
  ;; Maps each curve's lowercase :CURVE-ID (data/pilot-landmarks.sexp's :id,
  ;; downcased -- see EVIDENCE-WINDOW-RECORDS in src/evidence-windows.lisp)
  ;; to a clinical family key. Several curve-ids can share one family: both
  ;; PALETTE arms (sts-pazopanib, sts-placebo) map to the same key because
  ;; they are the same disease and neither one is a majority of the cluster
  ;; they land in alone, only the pair together is.
  '(("desmoid-sorafenib" . :desmoid-sorafenib)
    ("desmoid-placebo" . :desmoid-placebo)
    ("sts-pazopanib" . :sts-advanced-death)
    ("sts-placebo" . :sts-advanced-death)
    ("osteosarcoma-map" . :osteosarcoma)
    ("chondrosarcoma-ivosidenib" . :chondrosarcoma)
    ("gist-imatinib-400" . :gist)
    ("gist-imatinib-800" . :gist)
    ;; Hardy et al. 2025 (SEER 9, 10.1002/cncr.35906) contributes 12 curves:
    ;; STS local/distant-stage x 3 time periods, and GIST local/distant-stage
    ;; x 3 time periods. Once :MAXIMUM-OBSERVATIONS was widened (see
    ;; smc/pilot-search.sexp) to admit all 12 rather than just the first
    ;; (sts-local-1999-2004), the deployed clustering (seed 20260908) groups
    ;; all six STS curves (local and distant stage alike) together --
    ;; SURVIVAL-PROGRESS-DELTA is close to zero for all of them, so there is
    ;; nothing in this feature set to tell local-stage and distant-stage STS
    ;; apart -- while it splits GIST cleanly into a local-stage group and a
    ;; separate distant-stage group, since GIST's real improvement over time
    ;; differs by stage. The family split below follows that actual
    ;; structure rather than imposing a finer distinction the data doesn't
    ;; support.
    ("sts-local-1999-2004" . :sts-historical-trend)
    ("sts-local-2005-2011" . :sts-historical-trend)
    ("sts-local-2012-2019" . :sts-historical-trend)
    ("sts-distant-1999-2004" . :sts-historical-trend)
    ("sts-distant-2005-2011" . :sts-historical-trend)
    ("sts-distant-2012-2019" . :sts-historical-trend)
    ("gist-local-1999-2004" . :gist-historical-trend-local)
    ("gist-local-2005-2011" . :gist-historical-trend-local)
    ("gist-local-2012-2019" . :gist-historical-trend-local)
    ("gist-distant-1999-2004" . :gist-historical-trend-distant)
    ("gist-distant-2005-2011" . :gist-historical-trend-distant)
    ("gist-distant-2012-2019" . :gist-historical-trend-distant)))

(defparameter *sarcoma-clinical-cluster-names*
  ;; (FAMILY-KEY SHORT-NAME LONG-NOTE) per family key above, used in place of
  ;; the auto-generated feature-based name (SARCOMA-NAME-FROM-PHRASES)
  ;; whenever a cluster is clearly dominated by one family -- see
  ;; SARCOMA-CLUSTER-DOMINANT-FAMILY. SHORT-NAME is what the legend shows
  ;; next to each cluster's swatch (kept brief, like the feature-based names
  ;; it replaces); LONG-NOTE is the fuller clinical context shown on hover.
  ;; LONG-NOTE deliberately distinguishes "this disease cannot metastasize
  ;; or kill" (true of Desmoid) from "this disease is malignant but this
  ;; particular trial did not track death as its endpoint" (true of the
  ;; chondrosarcoma trial here) -- the two read very differently to a
  ;; clinician and should not be collapsed into one "progression-endpoint"
  ;; bucket just because they share EVENT-CODE 0.
  '((:desmoid-sorafenib
     "Desmoid tumor (Sorafenib) -- benign, drug-responsive"
     "Desmoid tumor, sorafenib: locally aggressive but does not metastasize and is very rarely life-threatening; sorafenib is an active drug that can shrink the tumor or control symptoms (higher objective response than placebo in this evidence).")
    (:desmoid-placebo
     "Desmoid tumor (no drug) -- benign, often stable untreated"
     "Desmoid tumor, no active drug: locally aggressive but does not metastasize and is very rarely life-threatening; many cases stay stable or regress on watchful waiting alone, without needing medicine.")
    (:sts-advanced-death
     "Soft-tissue sarcoma (Pazopanib/Placebo) -- advanced, life-threatening"
     "Advanced soft-tissue sarcoma, PALETTE trial (pazopanib vs. placebo): a life-threatening, metastatic disease tracked by overall survival; pazopanib delayed progression but did not extend survival over placebo here, which is why both arms sit together in this cluster.")
    (:osteosarcoma
     "Bone sarcoma (Osteosarcoma) -- life-threatening, often pediatric"
     "Bone sarcoma, osteosarcoma, EURAMOS-1 trial: a life-threatening disease tracked by overall survival; historically most common in children, adolescents, and young adults.")
    (:chondrosarcoma
     "Bone sarcoma (Chondrosarcoma) -- malignant, progression-tracked"
     "Bone sarcoma, advanced chondrosarcoma, ivosidenib trial: a malignant, potentially life-threatening bone cancer; this trial tracked disease progression/response rather than overall survival, which is why its evidence is coded like a progression endpoint here -- that reflects this trial's reporting, not a claim that chondrosarcoma is non-lethal the way Desmoid tumor is.")
    (:gist
     "GIST (Imatinib) -- malignant, effective targeted therapy"
     "GIST (gastrointestinal stromal tumor), imatinib: a malignant tumor with an established, effective targeted drug; one of the few sarcoma types here with a durable survival benefit from treatment.")
    (:sts-historical-trend
     "Population benchmark -- STS/bone sarcoma, no progress in 25 years"
     "Population-level historical benchmark, Hardy et al. 2025 (SEER 9, 10.1002/cncr.35906): soft-tissue and bone sarcoma survival by diagnosis period (1999-2019), localized and distant stage alike -- not an individual patient or treatment arm. Hardy et al.'s central finding: unlike GIST, this population's survival did not meaningfully improve over the 25-year period; local-stage and distant-stage curves land in the same cluster here because that near-zero trend is essentially identical for both.")
    (:gist-historical-trend-local
     "Population benchmark -- localized GIST, survival improving"
     "Population-level historical benchmark, Hardy et al. 2025 (SEER 9, 10.1002/cncr.35906): localized (non-metastatic) GIST survival by diagnosis period (1999-2019), not an individual patient or treatment arm. Unlike the STS/bone benchmark above, this population's survival measurably improved across the period covered -- consistent with imatinib's introduction as an effective targeted therapy.")
    (:gist-historical-trend-distant
     "Population benchmark -- distant/metastatic GIST, survival improving"
     "Population-level historical benchmark, Hardy et al. 2025 (SEER 9, 10.1002/cncr.35906): distant-stage (metastatic) GIST survival by diagnosis period (1999-2019), not an individual patient or treatment arm. This population also shows real improvement over time, and lands in its own cluster separate from localized-stage GIST -- the model distinguishes stage at diagnosis for GIST even though it can't for the STS/bone benchmark above.")))

(defun sarcoma-cluster-dominant-family (members &key (threshold 0.6d0))
  "MEMBERS: atlas-point plists for one real (non-noise) cluster. Returns the
clinical family key that accounts for at least THRESHOLD of the cluster's
members by curve identity, or NIL if no family reaches that bar (a
genuinely mixed cluster, which keeps its auto-generated feature-based
name instead)."
  (let ((counts (make-hash-table :test #'eql)) (total (length members)))
    (dolist (member members)
      (let* ((curve-id (getf (getf member :evidence) :curve-id))
             (family (cdr (assoc curve-id *sarcoma-curve-family* :test #'string=))))
        (when family (incf (gethash family counts 0)))))
    (let ((best nil) (best-count 0))
      (maphash (lambda (family count)
                 (when (> count best-count) (setf best family best-count count)))
               counts)
      (and best (>= (/ best-count total) threshold) best))))

(defun sarcoma-page-data (corpus weights)
  (let* ((source (parametric-open-corpus-source corpus))
         (metadata (parametric-source-metadata source))
         (schema (getf metadata :feature-schema))
         (artifact (predict-read-form weights))
         (pre (getf artifact :preprocessing))
         (result (predict-read-form (merge-pathnames (getf metadata :source-result) *sarcoma-root*)))
         ;; :MANIFEST in the AWRS-SMC result is the absolute path of the
         ;; manifest file on whatever machine last ran the search (here,
         ;; a stale "/Users/.../codex-sand/..." from before this checkout
         ;; was renamed to "csand"). Re-resolving just its filename against
         ;; *SARCOMA-ROOT* keeps this working after a clone or a rename,
         ;; instead of trusting that recorded absolute path verbatim.
         (manifest (merge-pathnames (file-namestring (getf result :manifest)) *sarcoma-root*))
         (problem (read-form-file manifest))
         (spec (getf problem :data))
         (raw (read-dataset (merge-pathnames (getf spec :file) manifest) spec))
         (by-id (make-hash-table :test #'equal)) (records nil) (atlas nil))
    (unless (and (equalp schema (getf artifact :feature-schema))
                 (equalp (getf metadata :preprocessing) pre))
      (error "Corpus and model feature schema/preprocessing differ."))
    (dolist (row raw)
      (when (gethash (getf row :id) by-id) (error "Duplicate evidence ID."))
      (setf (gethash (getf row :id) by-id) row))
    (parametric-map-records source (lambda (record) (push record records)))
    (setf records (nreverse records))
    (dolist (record records)
      (let ((row (or (gethash (getf record :id) by-id) (error "Missing evidence record."))))
        (push (list :id (getf record :id) :label (getf record :label)
                    :cluster (getf record :cluster)
                    :x (first (getf record :target)) :y (second (getf record :target))
                    :evidence row
                    :raw-values (loop for f in schema collect (nth (getf f :column) (getf row :vector)))
                    :input (getf record :input)) atlas)))
    (setf atlas (nreverse atlas))
    (list :problem problem :atlas atlas
          :features
          (loop for f in schema for i from 0
                for mean in (getf pre :means) for scale in (getf pre :scales)
                for values = (mapcar (lambda (p) (nth i (getf p :raw-values))) atlas)
                for raw-name = (string (getf f :name))
                for override = (assoc raw-name *sarcoma-feature-display-overrides* :test #'string=)
                collect (list :name (string-downcase raw-name)
                              :label (if override (second override)
                                        (substitute #\Space #\- (string-capitalize raw-name)))
                              :unit (if override (third override) "feature units")
                              :decimals (if override (fourth override) 4)
                              :raw-min (reduce #'min values) :raw-max (reduce #'max values)
                              :raw-mean (/ (reduce #'+ values) (length values))
                              :mean mean :scale scale :transformation (getf f :transformation)))
          :clusters
          (let* ((raw-clusters
                   (loop for c in (remove-duplicates (mapcar (lambda (p) (getf p :cluster)) atlas))
                         for members = (remove-if-not (lambda (p) (= c (getf p :cluster))) atlas)
                         for cx = (/ (reduce #'+ members :key (lambda (p) (getf p :x))) (length members))
                         for cy = (/ (reduce #'+ members :key (lambda (p) (getf p :y))) (length members))
                         for representative = (first (sort (copy-list members) #'< :key
                           (lambda (p) (+ (expt (- (getf p :x) cx) 2) (expt (- (getf p :y) cy) 2)))))
                         ;; Mean of the members' own standardized :INPUT
                         ;; vectors, in SCHEMA order -- what
                         ;; SARCOMA-CLUSTER-RANKED-PHRASES ranks to name the
                         ;; cluster after its defining features, as opposed
                         ;; to NAME below (the one representative record
                         ;; used as the "click this cluster" slider-seeding
                         ;; target).
                         for profile = (loop for column below (length schema)
                                            collect (/ (reduce #'+ members :key
                                                               (lambda (p) (nth column (getf p :input))))
                                                       (length members)))
                         collect (list :cluster c :name (getf representative :id)
                                       :raw-values (getf representative :raw-values)
                                       :phrases (sarcoma-cluster-ranked-phrases schema profile)
                                       :clinical-family (and (not (eql c -1))
                                                             (sarcoma-cluster-dominant-family members)))))
                 ;; Cluster -1 is DBSCAN noise -- "does not reliably belong
                 ;; to any cluster" -- so its members share no real feature
                 ;; profile by construction; every other cluster is named
                 ;; after what characterizes its members as a group, made
                 ;; distinct from every other real cluster's name (see
                 ;; SARCOMA-DISAMBIGUATE-NAMES), rather than after whichever
                 ;; one member happens to sit nearest its centroid.
                 (names (sarcoma-disambiguate-names
                         (loop for r in raw-clusters unless (eql (getf r :cluster) -1)
                               collect (cons (getf r :cluster) (getf r :phrases))))))
            (loop for r in raw-clusters
                  for family = (getf r :clinical-family)
                  for clinical = (assoc family *sarcoma-clinical-cluster-names*)
                  collect (list :cluster (getf r :cluster) :name (getf r :name)
                                :display-name
                                (cond ((eql (getf r :cluster) -1) "Insufficient evidence")
                                      (clinical (second clinical))
                                      (t (cdr (assoc (getf r :cluster) names))))
                                :clinical-note (and clinical (third clinical))
                                :raw-values (getf r :raw-values))))
          :model (preferences-model-json-plist (form-parametric-model (getf artifact :model))))))

(defun build-sarcoma-page (corpus weights output)
  (let* ((data (sarcoma-page-data corpus weights))
         (page (file-text (merge-pathnames "preferences-template.html" *sarcoma-directory*))))
    (loop for (marker key) on '("__ATLAS_POINTS__" :atlas "__FEATURES__" :features
                                "__CLUSTERS__" :clusters "__MODEL__" :model "__PROBLEM__" :problem)
          by #'cddr do
      (setf page (replace-marker page marker (with-output-to-string (s) (write-json-pretty (getf data key) s)))))
    (ensure-directories-exist output)
    (with-open-file (s output :direction :output :if-exists :supersede) (write-string page s))
    (format t "Wrote ~D atlas records with complete evidence and curves to ~A.~%" (length (getf data :atlas)) output)))
(defvar *sarcoma-page-run-main* t)
(when *sarcoma-page-run-main*
  (let ((args (cdr sb-ext:*posix-argv*)))
    (unless (= (length args) 3) (error "Expected CORPUS MODEL OUTPUT.html"))
    (apply #'build-sarcoma-page args)))
