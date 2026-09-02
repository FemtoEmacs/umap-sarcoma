(defparameter *parametric-tests-root*
  (merge-pathnames "../" (make-pathname :name nil :type nil
                                         :defaults *load-truename*)))

(defparameter *validate-parametric-corpus-run-main* nil)
(let ((*load-verbose* nil))
  (load (merge-pathnames "smc-trainer/validate-corpus.lisp"
                         *parametric-tests-root*)))

(test-cases:deftest generated-parametric-corpus-is-valid
  (let* ((path (merge-pathnames "smc-trainer/corpus/pilot-parametric-umap.sexp"
                                *parametric-tests-root*))
         (corpus (validate-parametric-corpus path))
         (records (getf corpus :records)))
    (test-cases:check-equal 90 (length records))
    (test-cases:check-equal 6 (length (getf (first records) :input)))
    (test-cases:check-equal 2 (length (getf (first records) :target)))
    (test-cases:check
     (every (lambda (record) (integerp (getf record :cluster))) records))))

(test-cases:deftest parametric-corpus-groups-do-not-cross-splits
  (let* ((corpus (corpus-read-form
                  (merge-pathnames
                   "smc-trainer/corpus/pilot-parametric-umap.sexp"
                   *parametric-tests-root*)))
         (records (getf corpus :records)))
    (dolist (left records)
      (dolist (right records)
        (when (equal (getf left :group) (getf right :group))
          (test-cases:check-equal (getf left :split) (getf right :split)))))))
