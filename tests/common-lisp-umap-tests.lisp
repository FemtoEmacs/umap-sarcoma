(defparameter *score-umap-run-main* nil)
(load "score-umap.lisp")

(defun cl-umap-test-finite-p (value)
  (and (realp value) (= value value)
       (< (abs value) most-positive-double-float)))

(test-cases:deftest cl-umap-standardization
  (let* ((input #2A((1.0d0 10.0d0) (2.0d0 10.0d0) (3.0d0 10.0d0)))
         (result (cl-umap-standardize input)))
    (test-cases:check (< (abs (+ (aref result 0 0)
                                  (aref result 1 0)
                                  (aref result 2 0)))
                             1.0d-12))
    (dotimes (row 3)
      (test-cases:check (= 0.0d0 (aref result row 1))))))

(test-cases:deftest cl-umap-exact-neighbor-order
  (multiple-value-bind (indices distances)
      (cl-umap-exact-neighbors #2A((0.0d0) (2.0d0) (5.0d0)) 3)
    (test-cases:check-equal 0 (aref indices 0 0))
    (test-cases:check-equal 1 (aref indices 0 1))
    (test-cases:check-equal 2 (aref indices 0 2))
    (test-cases:check (= 0.0d0 (aref distances 0 0)))
    (test-cases:check (= 2.0d0 (aref distances 0 1)))
    (test-cases:check (= 5.0d0 (aref distances 0 2)))))

(test-cases:deftest cl-umap-fuzzy-graph-symmetric
  (let ((input #2A((0.0d0) (0.1d0) (3.0d0) (3.1d0))))
    (multiple-value-bind (indices distances)
        (cl-umap-exact-neighbors input 3)
      (multiple-value-bind (sigmas rhos)
          (cl-umap-smooth-distances distances 3)
        (let ((graph (cl-umap-fuzzy-graph indices distances sigmas rhos)))
          (dotimes (row 4)
            (dotimes (column 4)
              (test-cases:check
               (< (abs (- (aref graph row column)
                          (aref graph column row)))
                  1.0d-12))
              (test-cases:check
               (<= 0.0d0 (aref graph row column) 1.0d0)))))))))

(test-cases:deftest cl-umap-deterministic-small-fit
  (let* ((input #2A((0.0d0 0.0d0) (0.1d0 0.0d0) (0.0d0 0.1d0)
                    (4.0d0 4.0d0) (4.1d0 4.0d0) (4.0d0 4.1d0)))
         (first (cl-umap-fit input :neighbors 3 :epochs 30 :seed 17))
         (second (cl-umap-fit input :neighbors 3 :epochs 30 :seed 17))
         (a (cl-umap-result-coordinates first))
         (b (cl-umap-result-coordinates second)))
    (dotimes (row 6)
      (dotimes (column 2)
        (test-cases:check (cl-umap-test-finite-p (aref a row column)))
        (test-cases:check (= (aref a row column) (aref b row column)))))))

(test-cases:deftest dbscan-finds-two-clusters
  (let* ((coordinates #2A((0.0d0 0.0d0) (0.1d0 0.0d0) (0.0d0 0.1d0)
                          (3.0d0 3.0d0) (3.1d0 3.0d0) (3.0d0 3.1d0)))
         (assignments (embedding-dbscan coordinates 0.25d0 2)))
    (test-cases:check-equal #(0 0 0 1 1 1) assignments
                            :test #'equalp)))

(test-cases:deftest cluster-classification-counts-labels
  (let* ((assignments #(0 0 0 1 1 1))
         (labels #(:soft :soft :gist :bone :bone :bone))
         (clusters (embedding-classify-clusters assignments labels)))
    (test-cases:check-equal 2 (length clusters))
    (test-cases:check-equal :soft
                            (embedding-cluster-dominant-label
                             (first clusters)))
    (test-cases:check-equal :bone
                            (embedding-cluster-dominant-label
                             (second clusters)))
    (test-cases:check (= 1.0d0
                         (embedding-cluster-purity (second clusters))))))

(test-cases:deftest cl-umap-invalid-parameters
  (test-cases:check-signals error
    (cl-umap-fit #2A((0.0d0) (1.0d0) (2.0d0)) :neighbors 3))
  (test-cases:check-signals error
    (embedding-dbscan #2A((0.0d0 0.0d0)) 0.0d0 2)))

(test-cases:deftest manifest-driven-umap-score
  (let ((output "tests/tmp/general-score-result.sexp"))
    (ensure-directories-exist output)
    (score-umap-manifest "tests/fixtures/general-score-problem.sexp")
    (let ((result (read-form-file output)))
      (test-cases:check-equal 6 (getf result :observation-count))
      (test-cases:check-equal 3 (getf result :feature-count))
      (test-cases:check-equal :diagnosis (getf result :label-field))
      (test-cases:check-equal
       "tests/fixtures/general-score-data.sexp"
       (getf result :data-file)
       :test (lambda (expected actual)
               (search expected actual))))))

(test-cases:deftest score-output-inherits-manifest-name
  (test-cases:check-equal
   "/tmp/output/example-problem-score.sexp"
   (namestring
    (score-umap-default-output #P"/tmp/example-problem.sexp" nil #P"/tmp/"))
   :test #'string=))
