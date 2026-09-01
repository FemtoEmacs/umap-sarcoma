(load (merge-pathnames "smc-core.lisp"
                       (make-pathname :name nil :type nil :defaults *load-truename*)))

(test-cases:deftest deterministic-generator
  (let ((left (smc-make-random-state 17)) (right (smc-make-random-state 17)))
    (dotimes (index 50)
      (declare (ignorable index))
      (test-cases:check-equal (smc-random-integer 10000 left)
                              (smc-random-integer 10000 right)))))

(test-cases:deftest legal-decisions-enforce-cardinality
  (let ((feature (make-smc-feature :name :x :column 0
                                   :transformations '(:identity :log1p))))
    (test-cases:check-equal '(:exclude) (smc-legal-choices feature 3 8 1 3))
    (test-cases:check-equal '(:identity :log1p)
                            (smc-legal-choices feature 1 0 2 5))
    (test-cases:check-equal '(:exclude :identity :log1p)
                            (smc-legal-choices feature 1 4 2 5))))

(test-cases:deftest matching-prior-and-proposal-cancel
  (let ((state (smc-make-random-state 9)))
    (dotimes (index 100)
      (declare (ignorable index))
      (multiple-value-bind (choice log-p log-q)
          (smc-propose-choice '(:exclude :identity :asinh) state)
        (test-cases:check (member choice '(:exclude :identity :asinh)))
        (test-cases:check-equal log-p log-q)))))

(test-cases:deftest optimal-c-solves-inclusion-equation
  (dolist (case '((#(0.25d0 0.25d0 0.25d0 0.25d0) 2)
                  (#(0.70d0 0.10d0 0.08d0 0.07d0 0.05d0) 3)
                  (#(0.40d0 0.30d0 0.20d0 0.10d0) 1)))
    (destructuring-bind (weights retained) case
      (let ((c (smc-find-optimal-c weights retained)))
        (test-cases:check
         (< (abs (- (loop for weight across weights
                          sum (min 1.0d0 (* c weight))) retained))
            1.0d-10))))))

(test-cases:deftest optimal-resampling-count-and-distinctness
  (let ((state (smc-make-random-state 99))
        (weights #(0.60d0 0.10d0 0.08d0 0.07d0 0.06d0 0.05d0 0.04d0)))
    (dotimes (trial 100)
      (declare (ignorable trial))
      (multiple-value-bind (deterministic stochastic c)
          (smc-optimal-resample-indices weights 4 state)
        (declare (ignore c))
        (let ((all (append deterministic stochastic)))
          (test-cases:check-equal 4 (length all))
          (test-cases:check-equal 4 (length (remove-duplicates all))))))))

(test-cases:deftest logsumexp-is-stable
  (let ((value (smc-logsumexp '(1000.0d0 1000.0d0))))
    (test-cases:check (< (abs (- value (+ 1000.0d0 (log 2.0d0)))) 1.0d-12))))

(test-cases:deftest exact-smc-completes-valid-configurations
  (let* ((features
           (loop for column below 6
                 collect (make-smc-feature :name (intern (format nil "F~D" column))
                                           :column column
                                           :transformations '(:identity))))
         (result
           (smc-run-search
            features
            (lambda (choices)
              (loop for choice in choices for index from 0
                    sum (if (member index '(0 2 4))
                            (if (eq choice :exclude) 0.0d0 1.0d0)
                            (if (eq choice :exclude) 0.0d0 -1.0d0))))
            :particle-count 12 :beam-factor 4
            :minimum-features 1 :maximum-features 5 :beta 5.0d0 :seed 7)))
    (test-cases:check-equal 6 (length (smc-search-result-history result)))
    (test-cases:check (plusp (smc-search-result-evaluations result)))
    (dolist (particle (smc-search-result-particles result))
      (test-cases:check-equal 6 (length (smc-particle-choices particle)))
      (test-cases:check
       (<= 1 (smc-choice-count (smc-particle-choices particle)) 5)))))
