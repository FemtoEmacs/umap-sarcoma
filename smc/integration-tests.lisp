(defparameter *smc-search-run-main* nil)
(load (merge-pathnames "search-umap.lisp"
                       (make-pathname :name nil :type nil
                                      :defaults *load-truename*)))

(test-cases:deftest unsafe-domain-transformations-stop
  (test-cases:check-signals error (smc-transform-value :log1p -0.1d0))
  (test-cases:check-signals error (smc-transform-value :sqrt -0.1d0))
  (test-cases:check-signals error
    (smc-transform-value :protected-logit 1.1d0)))

(test-cases:deftest signed-transformations-accept-negative-values
  (test-cases:check (realp (smc-transform-value :signed-log1p -8.0d0)))
  (test-cases:check (realp (smc-transform-value :asinh -8.0d0))))

(test-cases:deftest pilot-declarations-fit-data
  (let* ((search-path (merge-pathnames "pilot-search.sexp" *smc-directory*))
         (specification (smc-read-form search-path))
         (manifest-path (truename (merge-pathnames
                                   (getf specification :manifest)
                                   *smc-directory*)))
         (problem (read-form-file manifest-path))
         (manifest-directory (make-pathname :name nil :type nil
                                             :defaults manifest-path))
         (data-spec (getf problem :data))
         (records (read-dataset
                   (merge-pathnames (getf data-spec :file) manifest-directory)
                   data-spec))
         (input (score-umap-record-array records))
         (features
           (mapcar (lambda (form)
                     (smc-feature-from-form form (array-dimension input 1)))
                   (getf specification :features))))
    ;; Every declared transform must be defined on every value in its column.
    (dolist (feature features)
      (dolist (transformation (smc-feature-transformations feature))
        (dotimes (row (array-dimension input 0))
          (test-cases:check
           (realp (smc-transform-value
                   transformation
                   (aref input row (smc-feature-column feature))))
           "declared transformation is valid throughout its feature column"))))))
