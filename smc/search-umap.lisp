;;;; Search UMAP feature subsets and whitelisted transformations with SMC.

(defparameter *smc-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *smc-root* (merge-pathnames "../" *smc-directory*))
(defvar *smc-search-run-main* t)

(load (merge-pathnames "smc-core.lisp" *smc-directory*))
(defparameter *score-umap-run-main* nil)
(load (merge-pathnames "score-umap.lisp" *smc-root*))

(defun smc-read-form (path)
  (with-open-file (stream path :direction :input)
    (let ((*read-eval* nil))
      (or (read stream nil nil)
          (error "Empty SMC search file ~A." path)))))

(defun smc-feature-from-form (form column-count)
  (smc-validate-feature
   (make-smc-feature :name (getf form :name)
                     :column (getf form :column)
                     :transformations (getf form :transformations))
   column-count))

(defun smc-safe-log1p (value)
  (unless (>= value 0.0d0)
    (error "LOG1P received negative value ~S." value))
  (log (+ 1.0d0 value)))

(defun smc-protected-logit (value)
  (unless (<= 0.0d0 value 1.0d0)
    (error "PROTECTED-LOGIT requires a value in [0,1], got ~S." value))
  (let ((p (min (- 1.0d0 1.0d-9) (max 1.0d-9 value))))
    (log (/ p (- 1.0d0 p)))))

(defun smc-signed-log1p (value)
  (* (if (minusp value) -1.0d0 1.0d0)
     (log (+ 1.0d0 (abs value)))))

(defun smc-transform-value (name value)
  (let ((x (coerce value 'double-float)))
    (case name
      (:identity x)
      (:log1p (smc-safe-log1p x))
      (:sqrt (progn
               (unless (>= x 0.0d0)
                 (error "SQRT received negative value ~S." x))
               (sqrt x)))
      (:protected-logit (smc-protected-logit x))
      (:signed-log1p (smc-signed-log1p x))
      (:asinh (asinh x))
      (otherwise (error "Unknown transformation ~S." name)))))

(defun smc-selected-feature-array (input features choices observation-limit)
  (let* ((rows (array-dimension input 0))
         (used-rows (if observation-limit (min rows observation-limit) rows))
         (selected
           (loop for feature in features for choice in choices
                 unless (eq choice :exclude) collect (cons feature choice)))
         (output (make-array (list used-rows (length selected))
                             :element-type 'double-float)))
    (loop for row below used-rows do
      (loop for (feature . transformation) in selected
            for column from 0 do
        (setf (aref output row column)
              (smc-transform-value
               transformation
               (aref input row (smc-feature-column feature))))))
    output))

(defun smc-truncated-labels (labels observation-limit)
  (let* ((count (length labels))
         (used (if observation-limit (min count observation-limit) count))
         (result (make-array used)))
    (replace result labels :end2 used)
    result))

(defun smc-quality-components (input labels features choices settings
                               &key include-coordinates)
  (let* ((limit (getf settings :maximum-observations))
         (selected (smc-selected-feature-array input features choices limit))
         (used-labels (smc-truncated-labels labels limit))
         (umap (cl-umap-fit
                selected
                :neighbors (or (getf settings :neighbors) 15)
                :minimum-distance (or (getf settings :minimum-distance) 0.1d0)
                :epochs (or (getf settings :epochs) 50)
                :seed (or (getf settings :umap-seed) 42)
                :standardize (not (null (getf settings :standardize t)))))
         (clustering (embedding-find-and-classify
                      (cl-umap-result-coordinates umap) used-labels
                      :minimum-points (or (getf settings :minimum-points) 5)
                      :epsilon (let ((value (getf settings :epsilon :automatic)))
                                 (unless (eq value :automatic) value))))
         (measure (umap-v-measure-from-vectors
                   used-labels
                   (embedding-clustering-result-assignments clustering)))
         (v (umap-v-measure-result-v-measure measure))
         (feature-penalty (* (or (getf settings :feature-penalty) 0.0d0)
                             (smc-choice-count choices)))
         (adjacency-cost
           (embedding-cluster-adjacency-cost
            (cl-umap-result-coordinates umap)
            (embedding-clustering-result-assignments clustering)
            (embedding-clustering-result-epsilon clustering))))
    (append
     (list :score (- v feature-penalty)
           :quality (- v feature-penalty)
           :v-measure v
           :feature-penalty feature-penalty
           :adjacency-cost adjacency-cost
           :cluster-count (embedding-clustering-result-cluster-count clustering))
     (when include-coordinates
       (list :coordinate-source :common-lisp-umap
             :coordinates (cl-umap-result-coordinates umap))))))

(defun smc-quality (input labels features choices settings)
  (getf (smc-quality-components input labels features choices settings)
        :quality))

(defun smc-choice-description (features choices)
  (loop for feature in features for choice in choices
        unless (eq choice :exclude)
          collect (list :name (smc-feature-name feature)
                        :column (smc-feature-column feature)
                        :transformation choice)))

(defun smc-result-form (search-path manifest-path features settings result)
  (list :format :umap-smc-search-result :version 1
        :search-file (namestring search-path)
        :manifest (namestring manifest-path)
        :algorithm :lew-et-al-smc-steering
        :reference
        (list :paper "https://arxiv.org/abs/2306.03081"
              :implementation "https://github.com/probcomp/llamppl"
              :implementation-commit
              "4c57886b9ce776254d762f70d61891e59498a00f")
        :probabilistic-model
        (list :state :partial-feature-decision-sequence
              :proposal :uniform-over-legal-decisions
              :prior :same-as-proposal
              :terminal-potential :exp-beta-times-score
              :target :prior-times-terminal-potential
              :resampling :fearnhead-clifford-optimal)
        :settings settings
        :evaluations (smc-search-result-evaluations result)
        :cache-hits (smc-search-result-cache-hits result)
        :history (smc-search-result-history result)
        :best
        (let ((particle (smc-search-result-best-particle result)))
          (list :score (smc-particle-score particle)
                :features (smc-choice-description
                           features (smc-particle-choices particle))))
        :particles
        (mapcar (lambda (particle)
                  (list :score (smc-particle-score particle)
                        :weight (smc-particle-weight particle)
                        :features (smc-choice-description
                                   features (smc-particle-choices particle))))
                (smc-search-result-particles result))))

(defun smc-default-output (search-path)
  (merge-pathnames
   (format nil "~A-result.sexp" (pathname-name search-path))
   (make-pathname :name nil :type nil :defaults search-path)))

(defun smc-search-umap (search-name &optional output-name)
  (let* ((search-path (truename search-name))
         (search-directory (make-pathname :name nil :type nil
                                          :defaults search-path))
         (specification (smc-read-form search-path))
         (manifest-path
           (truename (merge-pathnames (getf specification :manifest)
                                      search-directory)))
         (problem (read-form-file manifest-path))
         (manifest-directory (make-pathname :name nil :type nil
                                             :defaults manifest-path))
         (data-spec (getf problem :data))
         (records (read-dataset
                   (merge-pathnames (getf data-spec :file) manifest-directory)
                   data-spec))
         (input (score-umap-record-array records))
         (label-field (or (getf specification :label-field)
                          (getf (getf problem :scoring) :label-field)))
         (labels (score-umap-label-vector records label-field))
         (feature-forms (getf specification :features))
         (features (mapcar (lambda (form)
                             (smc-feature-from-form
                              form (array-dimension input 1)))
                           feature-forms))
         (settings (getf specification :search))
         (result
           (smc-run-search
            features
            (lambda (choices)
              (smc-quality input labels features choices settings))
            :particle-count (or (getf settings :particles) 4)
            :beam-factor (or (getf settings :beam-factor) 3)
            :minimum-features (or (getf settings :minimum-features) 2)
            :maximum-features (getf settings :maximum-features)
            :beta (or (getf settings :beta) 8.0d0)
            :seed (or (getf settings :smc-seed) 20260901)))
         (output-path (if output-name (pathname output-name)
                          (smc-default-output search-path)))
         (form (smc-result-form search-path manifest-path features settings result)))
    (ensure-directories-exist output-path)
    (with-open-file (stream output-path :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
      (let ((*print-pretty* t) (*print-length* nil) (*print-level* nil))
        (prin1 form stream) (terpri stream)))
    (format t "SMC evaluations: ~D; cache hits: ~D.~%"
            (smc-search-result-evaluations result)
            (smc-search-result-cache-hits result))
    (format t "Best score: ~,6F~%Best features: ~S~%Wrote ~A~%"
            (smc-particle-score (smc-search-result-best-particle result))
            (smc-choice-description
             features
             (smc-particle-choices
              (smc-search-result-best-particle result)))
            output-path)
    (values result output-path)))

(defun smc-search-main ()
  (let ((arguments (cdr *posix-argv*)))
    (unless (<= 1 (length arguments) 2)
      (error "Usage: sbcl --script smc/search-umap.lisp SEARCH.sexp [OUTPUT.sexp]"))
    (smc-search-umap (first arguments) (second arguments))))

(when *smc-search-run-main* (smc-search-main))
