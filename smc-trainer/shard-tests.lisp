(defparameter *shard-tests-root*
  (merge-pathnames "../" (make-pathname :name nil :type nil :defaults *load-truename*)))

(defparameter *validate-parametric-corpus-run-main* nil)
(load (merge-pathnames "smc-trainer/validate-corpus.lisp" *shard-tests-root*))
(defparameter *parametric-train-run-main* nil)
(load (merge-pathnames "smc-trainer/train.lisp" *shard-tests-root*))
(defparameter *shard-corpus-run-main* nil)
(load (merge-pathnames "smc-trainer/shard-corpus.lisp" *shard-tests-root*))

(defun shard-test-record-ids (source)
  (let ((ids nil))
    (parametric-map-records source (lambda (record) (push (getf record :id) ids)))
    (nreverse ids)))

(test-cases:deftest shard-manifest-is-valid-and-equivalent
  (let* ((single-path (merge-pathnames
                       "smc-trainer/corpus/pilot-parametric-umap.sexp"
                       *shard-tests-root*))
         (manifest-path (merge-pathnames
                         "smc-trainer/corpus/pilot-shards/manifest.sexp"
                         *shard-tests-root*))
         (single (validate-parametric-corpus single-path))
         (sharded (validate-parametric-corpus manifest-path)))
    (test-cases:check-equal 90 (parametric-count-records sharded))
    (test-cases:check-equal (shard-test-record-ids single)
                            (shard-test-record-ids sharded))))

(test-cases:deftest sharded-training-reproduces-single-file-training
  (let* ((single (parametric-open-corpus-source
                  (merge-pathnames "smc-trainer/corpus/pilot-parametric-umap.sexp"
                                   *shard-tests-root*)))
         (sharded (parametric-open-corpus-source
                   (merge-pathnames "smc-trainer/corpus/pilot-shards/manifest.sexp"
                                    *shard-tests-root*))))
    (multiple-value-bind (single-model single-report)
        (train-parametric-source single :epochs 2 :learning-rate 0.002d0)
      (multiple-value-bind (sharded-model sharded-report)
          (train-parametric-source sharded :epochs 2 :learning-rate 0.002d0)
        (test-cases:check-equal (parametric-model-form single-model)
                                (parametric-model-form sharded-model))
        (test-cases:check-equal single-report sharded-report)))))

(test-cases:deftest interleaved-study-records-remain-in-one-group
  (let* ((a1 '(:id "a1" :group "A" :split :train))
         (b1 '(:id "b1" :group "B" :split :validation))
         (a2 '(:id "a2" :group "A" :split :train))
         (groups (shard-group-records (list a1 b1 a2))))
    (test-cases:check-equal '(("a1" "a2") ("b1"))
                            (mapcar (lambda (group)
                                      (mapcar (lambda (record) (getf record :id)) group))
                                    groups))))

(test-cases:deftest group-crossing-splits-is-rejected
  (test-cases:check-signals error
    (shard-group-records
     '((:id "a1" :group "A" :split :train)
       (:id "a2" :group "A" :split :validation)))))
