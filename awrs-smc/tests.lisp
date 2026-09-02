(defparameter cl-user::*awrs-smc-tests-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))

(load (merge-pathnames "awrs.lisp"
                       (make-pathname :name nil :type nil :defaults *load-truename*)))
(load (merge-pathnames "smc.lisp"
                       (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package :awrs-smc)

(test-cases:deftest distribution-validation
  (test-cases:check-signals error
    (validate-categorical-distribution '((:a . 0.7d0) (:b . 0.4d0))))
  (test-cases:check-signals error
    (validate-categorical-distribution '((:a . 0.5d0) (:a . 0.5d0))))
  (test-cases:check-equal '((:a . 0.6d0) (:b . 0.4d0))
                           (validate-categorical-distribution
                            '((:a . 0.6d0) (:b . 0.4d0)))))

(test-cases:deftest awrs-is-deterministic-for-a-seed
  (let* ((distribution '((:bad . 0.6d0) (:good-a . 0.25d0) (:good-b . 0.15d0)))
         (constraint (lambda (x) (not (eq x :bad))))
         (left (awrs-sample distribution constraint
                            :state (make-awrs-random-state 55)))
         (right (awrs-sample distribution constraint
                             :state (make-awrs-random-state 55))))
    (test-cases:check-equal (awrs-result-value left) (awrs-result-value right))
    (test-cases:check-equal (awrs-result-zhat left) (awrs-result-zhat right))
    (test-cases:check-equal (awrs-result-telemetry left)
                            (awrs-result-telemetry right))))

(test-cases:deftest always-valid-has-unit-weight
  (let ((result (awrs-sample '((:a . 0.3d0) (:b . 0.7d0))
                              (lambda (x) (declare (ignore x)) t)
                              :state (make-awrs-random-state 2)
                              :report-exact-z t)))
    (test-cases:check-equal 1.0d0 (awrs-result-zhat result))
    (test-cases:check-equal 1.0d0 (awrs-result-exact-z result))
    (test-cases:check-equal 2
                            (getf (awrs-result-telemetry result)
                                  :constraint-checks))))

(test-cases:deftest zhat-is-unbiased-on-finite-oracle
  (let* ((distribution '((:bad-a . 0.45d0) (:bad-b . 0.20d0)
                         (:good-a . 0.25d0) (:good-b . 0.10d0)))
         (constraint (lambda (x) (member x '(:good-a :good-b))))
         (exact (awrs-exact-acceptance-mass distribution constraint))
         (trials 20000)
         (mean
           (/ (loop for seed from 1 to trials
                    for result = (awrs-sample
                                  distribution constraint
                                  :state (make-awrs-random-state seed))
                    do (test-cases:check
                        (funcall constraint (awrs-result-value result)))
                    sum (awrs-result-zhat result))
              trials)))
    (test-cases:check (< (abs (- mean exact)) 0.01d0)
                      "Monte Carlo mean agrees with enumerated Z")))

(test-cases:deftest rejected-values-are-unique
  (let* ((distribution '((:bad-a . 0.4d0) (:bad-b . 0.3d0)
                         (:bad-c . 0.2d0) (:good . 0.1d0)))
         (result (awrs-sample distribution (lambda (x) (eq x :good))
                              :state (make-awrs-random-state 7)))
         (rejected (getf (awrs-result-telemetry result) :unique-rejections)))
    (test-cases:check-equal (length rejected)
                            (length (remove-duplicates rejected :test #'equal)))))

(test-cases:deftest resampling-uses-w-over-m
  (let* ((particles (list (make-awrs-particle :values '(:a) :weight 1.0d0)
                          (make-awrs-particle :values '(:b) :weight 2.0d0)
                          (make-awrs-particle :values '(:c) :weight 3.0d0)))
         (resampled (multinomial-resample particles (make-awrs-random-state 3))))
    (test-cases:check-equal 3 (length resampled))
    (dolist (particle resampled)
      (test-cases:check-equal 2.0d0 (awrs-particle-weight particle)))))

(test-cases:deftest terminal-potential-and-telemetry
  (let* ((result
           (run-awrs-smc
            (lambda (prefix)
              (if prefix '((:eos . 1.0d0))
                  '((:keep . 0.5d0) (:reject . 0.5d0))))
            (lambda (prefix value)
              (declare (ignore prefix))
              (not (eq value :reject)))
            :particle-count 4 :seed 71 :maximum-steps 2
            :terminal-potential-function
            (lambda (choices) (declare (ignore choices)) 3.0d0)))
         (telemetry (awrs-smc-result-telemetry result))
         (calls (loop for iteration in (getf telemetry :history)
                      append (getf iteration :awrs-calls))))
    (test-cases:check-equal 4 (getf telemetry :terminal-evaluations))
    (test-cases:check (plusp (getf telemetry :constraint-checks)))
    (test-cases:check-equal
     (getf telemetry :constraint-checks)
     (loop for call in calls sum (getf call :constraint-checks)))
    (test-cases:check-equal
     (getf telemetry :rejections)
     (loop for call in calls sum (getf call :total-rejections)))
    (dolist (particle (awrs-smc-result-particles result))
      (test-cases:check-equal '(:keep) (awrs-particle-values particle)))))
