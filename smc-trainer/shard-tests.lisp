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
  (let* ((manifest-path (merge-pathnames
                         "smc-trainer/corpus/pilot-shards/manifest.sexp"
                         *shard-tests-root*))
         (sharded (validate-parametric-corpus manifest-path))
         (metadata (parametric-source-metadata sharded)))
    (test-cases:check-equal 90 (parametric-count-records sharded))
    (test-cases:check (>= (length (getf metadata :shards)) 3))
    (test-cases:check (every (lambda (descriptor)
                              (plusp (getf descriptor :records)))
                            (getf metadata :shards)))
    (test-cases:check-equal 90 (length (shard-test-record-ids sharded)))))

(test-cases:deftest sharded-training-is-deterministic
  (let* ((sharded (parametric-open-corpus-source
                   (merge-pathnames "smc-trainer/corpus/pilot-shards/manifest.sexp"
                                    *shard-tests-root*))))
    (multiple-value-bind (first-model first-report)
        (train-parametric-source sharded :epochs 2 :learning-rate 0.002d0)
      (multiple-value-bind (second-model second-report)
          (train-parametric-source sharded :epochs 2 :learning-rate 0.002d0)
        (test-cases:check-equal (parametric-model-form first-model)
                                (parametric-model-form second-model))
        (test-cases:check-equal first-report second-report)))))

(defun shard-test-source (records)
  (list :kind :single :path "test" :metadata
        (list :format :parametric-umap-corpus :version 1 :records records)))

(test-cases:deftest interleaved-study-group-is-rejected
  (test-cases:check-signals error
    (shard-map-study-groups
     (shard-test-source
      '((:id "a1" :group "A" :split :train)
        (:id "b1" :group "B" :split :validation)
        (:id "a2" :group "A" :split :train)))
     (lambda (group split records) (declare (ignore group split records))))))

(test-cases:deftest group-crossing-splits-is-rejected
  (test-cases:check-signals error
    (shard-map-study-groups
     (shard-test-source
      '((:id "a1" :group "A" :split :train)
        (:id "a2" :group "A" :split :validation)))
     (lambda (group split records) (declare (ignore group split records))))))

(defun variable-shard-record (id group split value)
  (list :id id :group group :split split
        :input (list (coerce value 'double-float))
        :target (list (coerce value 'double-float) 0.0d0)
        :cluster 0 :label "Synthetic shard test"))

(defun write-variable-shard-source (path records)
  (with-open-file (stream path :direction :output :if-exists :supersede
                               :if-does-not-exist :create)
    (write (list :format :parametric-umap-stream-corpus :version 1
                 :feature-schema '((:name :synthetic))
                 :preprocessing '(:standardize t :means (0.0d0) :scales (1.0d0))
                 :split-policy '(:kind :study-grouped)
                 :record-count (length records))
           :stream stream)
    (terpri stream)
    (dolist (record records) (write record :stream stream) (terpri stream))))

(test-cases:deftest variable-record-count-builds-three-real-shards
  (let* ((source-path "/tmp/smc-trainer-seven-records.sexp")
         (output-directory "/tmp/smc-trainer-seven-shards/")
         (records
           (list (variable-shard-record "a1" "A" :train 1)
                 (variable-shard-record "a2" "A" :train 2)
                 (variable-shard-record "b1" "B" :train 3)
                 (variable-shard-record "b2" "B" :train 4)
                 (variable-shard-record "b3" "B" :train 5)
                 (variable-shard-record "c1" "C" :validation 6)
                 (variable-shard-record "c2" "C" :validation 7))))
    (write-variable-shard-source source-path records)
    (shard-corpus source-path output-directory :record-limit 2)
    (let* ((source (validate-parametric-corpus
                    (concatenate 'string output-directory "manifest.sexp")))
           (metadata (parametric-source-metadata source)))
      (test-cases:check-equal 7 (parametric-count-records source))
      (test-cases:check-equal 3 (length (getf metadata :shards)))
      (test-cases:check-equal '(2 3 2)
                              (mapcar (lambda (descriptor)
                                        (getf descriptor :records))
                                      (getf metadata :shards))))))
