;;;; Search real UMAP feature recipes with AWRS-SMC and save full telemetry.

(defparameter *awrs-umap-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *awrs-umap-root* (merge-pathnames "../" *awrs-umap-directory*))

(load (merge-pathnames "awrs.lisp" *awrs-umap-directory*))
(load (merge-pathnames "smc.lisp" *awrs-umap-directory*))

;; Reuse the real Common Lisp UMAP, DBSCAN, V-measure, manifest reader, and
;; transformation whitelist used by the published UMAP search.
(defparameter *smc-search-run-main* nil)
(load (merge-pathnames "smc/search-umap.lisp" *awrs-umap-root*))

(defvar *awrs-umap-run-main* t)

(defun awrs-uniform-distribution (values)
  (let ((probability (/ 1.0d0 (length values))))
    (mapcar (lambda (value) (cons value probability)) values)))

(defun awrs-selected-count (choices)
  (count-if-not (lambda (choice) (eq choice :exclude)) choices))

(defun awrs-legal-next-choice-p (prefix choice feature-count minimum maximum)
  (let* ((next-length (1+ (length prefix)))
         (selected (+ (awrs-selected-count prefix)
                      (if (eq choice :exclude) 0 1)))
         (remaining (- feature-count next-length)))
    (and (<= next-length feature-count)
         (<= selected maximum)
         (>= (+ selected remaining) minimum))))

(defun awrs-choice-description (features choices)
  (loop for feature in features for choice in choices
        unless (eq choice :exclude)
          collect (list :name (smc-feature-name feature)
                        :column (smc-feature-column feature)
                        :transformation choice)))

(defun awrs-default-output (search-path)
  (merge-pathnames
   (format nil "~A-awrs-result.sexp" (pathname-name search-path))
   (make-pathname :name nil :type nil :defaults search-path)))

(defun awrs-umap-result-form
    (search-path manifest-path features settings result scored-particles best)
  (list :format :umap-awrs-smc-search-result :version 1
        :search-file (namestring search-path)
        :manifest (namestring manifest-path)
        :algorithm :adaptive-weighted-rejection-sampling-smc
        :reference (list :paper "https://arxiv.org/abs/2504.05410"
                         :awrs-definition 2 :smc-algorithm 2)
        :settings settings
        :telemetry (awrs-smc:awrs-smc-result-telemetry result)
        :best (list :score (cdr best)
                    :features (awrs-choice-description
                               features
                               (awrs-smc:awrs-particle-values (car best))))
        :particles
        (mapcar
         (lambda (entry)
           (let ((particle (car entry)) (score (cdr entry)))
             (list :score score
                   :weight (awrs-smc:awrs-particle-weight particle)
                   :features (awrs-choice-description
                              features
                              (awrs-smc:awrs-particle-values particle)))))
         scored-particles)))

(defun awrs-search-umap (search-name &optional output-name)
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
         (features
           (mapcar (lambda (form)
                     (smc-feature-from-form form (array-dimension input 1)))
                   (getf specification :features)))
         (settings (getf specification :search))
         (feature-count (length features))
         (minimum (or (getf settings :minimum-features) 2))
         (maximum (or (getf settings :maximum-features) feature-count))
         (beta (or (getf settings :beta) 8.0d0))
         (score-cache (make-hash-table :test #'equal))
         (score-function
           (lambda (choices)
             (multiple-value-bind (value present) (gethash choices score-cache)
               (if present value
                   (setf (gethash (copy-list choices) score-cache)
                         (smc-quality input labels features choices settings))))))
         (result
           (awrs-smc:run-awrs-smc
            (lambda (prefix)
              (if (= (length prefix) feature-count)
                  '((:eos . 1.0d0))
                  (awrs-uniform-distribution
                   (cons :exclude
                         (smc-feature-transformations
                          (nth (length prefix) features))))))
            (lambda (prefix choice)
              (if (eq choice :eos)
                  (and (= (length prefix) feature-count)
                       (<= minimum (awrs-selected-count prefix) maximum))
                  (awrs-legal-next-choice-p
                   prefix choice feature-count minimum maximum)))
            :particle-count (or (getf settings :particles) 8)
            :resampling-threshold
            (or (getf settings :resampling-threshold) 0.5d0)
            :maximum-steps (1+ feature-count)
            :seed (or (getf settings :smc-seed) 20260901)
            :terminal-potential-function
            (lambda (choices) (exp (* beta (funcall score-function choices))))))
         (scored
           (mapcar (lambda (particle)
                     (cons particle
                           (funcall score-function
                                    (awrs-smc:awrs-particle-values particle))))
                   (awrs-smc:awrs-smc-result-particles result)))
         (best (reduce (lambda (left right)
                         (if (> (cdr left) (cdr right)) left right)) scored))
         (output-path (if output-name (pathname output-name)
                          (awrs-default-output search-path)))
         (form (awrs-umap-result-form search-path manifest-path features settings
                                      result scored best)))
    (ensure-directories-exist output-path)
    (with-open-file (stream output-path :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
      (let ((*print-pretty* t) (*print-length* nil) (*print-level* nil))
        (prin1 form stream) (terpri stream)))
    (let ((telemetry (awrs-smc:awrs-smc-result-telemetry result)))
      (format t "UMAP evaluations: ~D; constraint checks: ~D; rejections: ~D.~%"
              (hash-table-count score-cache)
              (getf telemetry :constraint-checks)
              (getf telemetry :rejections)))
    (format t "Best score: ~,6F~%Best features: ~S~%Wrote ~A~%"
            (cdr best)
            (awrs-choice-description
             features (awrs-smc:awrs-particle-values (car best)))
            output-path)
    output-path))

(defun awrs-search-main ()
  (let ((arguments (cdr sb-ext:*posix-argv*)))
    (unless (<= 1 (length arguments) 2)
      (error "Usage: sbcl --script awrs-smc/search-umap.lisp SEARCH.sexp [OUTPUT.sexp]"))
    (awrs-search-umap (first arguments) (second arguments))))

(when *awrs-umap-run-main* (awrs-search-main))

