(defparameter *parametric-tests-root*
  (merge-pathnames "../" (make-pathname :name nil :type nil
                                         :defaults *load-truename*)))

(defparameter *validate-parametric-corpus-run-main* nil)
(let ((*load-verbose* nil))
  (load (merge-pathnames "smc-trainer/validate-corpus.lisp"
                         *parametric-tests-root*)))

(test-cases:deftest generated-parametric-corpus-is-valid
  (let* ((path (merge-pathnames "smc-trainer/corpus/pilot-shards/manifest.sexp"
                                *parametric-tests-root*))
         (source (validate-parametric-corpus path))
         (record (parametric-first-record source)))
    (test-cases:check-equal 90 (parametric-count-records source))
    (test-cases:check-equal 6 (length (getf record :input)))
    (test-cases:check-equal 2 (length (getf record :target)))
    (parametric-map-records
     source (lambda (item)
              (test-cases:check (integerp (getf item :cluster)))))))

(test-cases:deftest parametric-corpus-groups-do-not-cross-splits
  (let* ((source (parametric-open-corpus-source
                  (merge-pathnames
                   "smc-trainer/corpus/pilot-shards/manifest.sexp"
                   *parametric-tests-root*)))
         (records nil))
    (parametric-map-records source (lambda (record) (push record records)))
    (dolist (left records)
      (dolist (right records)
        (when (equal (getf left :group) (getf right :group))
          (test-cases:check-equal (getf left :split) (getf right :split)))))))
