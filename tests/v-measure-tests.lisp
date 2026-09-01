(load "src/v-measure.lisp")

(defun v-test-close-p (expected actual &optional (tolerance 1.0d-9))
  (<= (abs (- expected actual)) tolerance))

(defun v-test-result (labels clusters &key (beta 1.0d0))
  (umap-v-measure-from-vectors labels clusters :beta beta))

(test-cases:deftest v-measure-perfect-partition
  (let ((result (v-test-result #(:a :a :b :b) #(9 9 4 4))))
    (test-cases:check
     (v-test-close-p 1.0d0
                     (umap-v-measure-result-homogeneity result)))
    (test-cases:check
     (v-test-close-p 1.0d0
                     (umap-v-measure-result-completeness result)))
    (test-cases:check
     (v-test-close-p 1.0d0
                     (umap-v-measure-result-v-measure result)))))

(test-cases:deftest v-measure-published-example
  (let ((result (v-test-result #(0 0 1 1 2 2) #(0 0 1 2 2 2))))
    (test-cases:check
     (v-test-close-p 0.71d0
                     (umap-v-measure-result-homogeneity result)
                     0.005d0))
    (test-cases:check
     (v-test-close-p 0.771d0
                     (umap-v-measure-result-completeness result)
                     0.005d0))
    (test-cases:check
     (v-test-close-p 0.74d0
                     (umap-v-measure-result-v-measure result)
                     0.005d0))))

(test-cases:deftest v-measure-one-cluster
  (let ((result (v-test-result #(:a :a :b :b) #(0 0 0 0))))
    (test-cases:check
     (v-test-close-p 0.0d0
                     (umap-v-measure-result-homogeneity result)))
    (test-cases:check
     (v-test-close-p 1.0d0
                     (umap-v-measure-result-completeness result)))
    (test-cases:check
     (v-test-close-p 0.0d0
                     (umap-v-measure-result-v-measure result)))))

(test-cases:deftest v-measure-fragmentation-penalty
  (let ((result (v-test-result #(:a :a :b :b) #(0 1 2 3))))
    (test-cases:check
     (v-test-close-p 1.0d0
                     (umap-v-measure-result-homogeneity result)))
    (test-cases:check
     (< (umap-v-measure-result-completeness result) 1.0d0))
    (test-cases:check
     (< (umap-v-measure-result-v-measure result) 1.0d0))))

(test-cases:deftest v-measure-beta-weights-completeness
  (let* ((labels #(0 0 1 1 2 2))
         (clusters #(0 0 1 2 2 2))
         (low (v-test-result labels clusters :beta 0.5d0))
         (high (v-test-result labels clusters :beta 2.0d0)))
    (test-cases:check
     (< (umap-v-measure-result-v-measure low)
        (umap-v-measure-result-v-measure high)))))

(test-cases:deftest v-measure-label-permutation-invariant
  (let ((first (v-test-result #(:a :a :b :b) #(0 0 1 1)))
        (second (v-test-result #(:x :x :y :y) #(7 7 3 3))))
    (test-cases:check
     (v-test-close-p
      (umap-v-measure-result-v-measure first)
      (umap-v-measure-result-v-measure second)))))

(test-cases:deftest v-measure-symmetric-at-beta-one
  (loop for split from 1 to 5 do
    (let* ((labels #(0 0 0 1 1 1))
           (clusters (if (oddp split)
                         #(0 0 1 1 2 2)
                         #(0 1 0 1 0 1)))
           (forward (v-test-result labels clusters))
           (reverse (v-test-result clusters labels)))
      (test-cases:check
       (v-test-close-p
        (umap-v-measure-result-v-measure forward)
        (umap-v-measure-result-v-measure reverse))))))

(test-cases:deftest v-measure-contingency-preserves-count
  (let* ((result (v-test-result #(:a :a :b :b :b) #(0 1 1 1 2)))
         (table (umap-v-measure-result-contingency result))
         (total (loop for row below (array-dimension table 0)
                      sum (loop for column below (array-dimension table 1)
                                sum (aref table row column)))))
    (test-cases:check-equal 5 total)
    (test-cases:check-equal 2 (array-dimension table 0))
    (test-cases:check-equal 3 (array-dimension table 1))))

(test-cases:deftest v-measure-score-input-end-to-end
  (let* ((coordinates (make-array '(4 2)
                                  :initial-contents
                                  '((0.0d0 0.0d0)
                                    (0.1d0 0.0d0)
                                    (2.0d0 2.0d0)
                                    (2.1d0 2.0d0))))
         (input (make-umap-score-input coordinates
                                       #(:a :a :b :b)
                                       #(0 0 1 1)))
         (result (score-umap-clusters input)))
    (test-cases:check-equal 4
                            (umap-v-measure-result-observation-count result))
    (test-cases:check
     (v-test-close-p 1.0d0
                     (umap-v-measure-result-v-measure result)))))

(test-cases:deftest v-measure-invalid-inputs
  (test-cases:check-signals error
    (umap-v-measure-from-vectors #() #()))
  (test-cases:check-signals error
    (umap-v-measure-from-vectors #(0 1) #(0)))
  (test-cases:check-signals error
    (umap-v-measure-from-vectors #(0 1) #(0 1) :beta 0))
  (test-cases:check-signals error
    (make-umap-score-input (make-array '(2 3)) #(0 1) #(0 1))))

(test-cases:deftest v-measure-range-invariant
  (dolist (clusters '(#(0 0 0 0 0 0)
                      #(0 0 1 1 2 2)
                      #(0 1 2 3 4 5)
                      #(0 1 0 1 0 1)))
    (let ((result (v-test-result #(0 0 1 1 2 2) clusters)))
      (dolist (value (list (umap-v-measure-result-homogeneity result)
                           (umap-v-measure-result-completeness result)
                           (umap-v-measure-result-v-measure result)))
        (test-cases:check (<= 0.0d0 value 1.0d0))))))
