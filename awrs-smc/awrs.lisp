;;;; Adaptive Weighted Rejection Sampling, Definition 2 of Lipkin et al. (2025).

(defpackage :awrs-smc
  (:use :cl)
  (:export
   #:make-awrs-random-state #:awrs-random-unit
   #:validate-categorical-distribution #:categorical-probability
   #:awrs-exact-acceptance-mass #:awrs-sample
   #:awrs-result #:awrs-result-value #:awrs-result-zhat
   #:awrs-result-exact-z #:awrs-result-telemetry
   #:run-awrs-smc #:awrs-smc-result #:awrs-smc-result-particles
   #:awrs-smc-result-selected #:awrs-smc-result-normalizer-estimate
   #:awrs-smc-result-telemetry
   #:awrs-particle #:awrs-particle-values #:awrs-particle-weight
   #:awrs-particle-active-p))

(in-package :awrs-smc)

(defstruct (awrs-random-state (:constructor %make-awrs-random-state (value)))
  (value 1 :type integer))

(defun make-awrs-random-state (&optional (seed 20260902))
  (unless (integerp seed) (error "The random seed must be an integer."))
  (%make-awrs-random-state (mod seed 4294967296)))

(defun awrs-random-unit (state)
  (setf (awrs-random-state-value state)
        (mod (+ (* 1664525 (awrs-random-state-value state)) 1013904223)
             4294967296))
  (/ (+ 0.5d0 (awrs-random-state-value state)) 4294967296.0d0))

(defun validate-categorical-distribution (distribution)
  (unless (consp distribution)
    (error "A categorical distribution must be a nonempty alist."))
  (let ((seen '()) (total 0.0d0))
    (dolist (entry distribution)
      (unless (and (consp entry) (realp (cdr entry))
                   (not (minusp (cdr entry))))
        (error "Invalid categorical entry ~S." entry))
      (when (member (car entry) seen :test #'equal)
        (error "Duplicate categorical outcome ~S." (car entry)))
      (push (car entry) seen)
      (incf total (coerce (cdr entry) 'double-float)))
    (unless (< (abs (- total 1.0d0)) 1.0d-12)
      (error "Categorical probabilities must sum to 1; found ~S." total)))
  distribution)

(defun categorical-probability (value distribution)
  (let ((entry (assoc value distribution :test #'equal)))
    (if entry (coerce (cdr entry) 'double-float)
        (error "Outcome ~S is absent from the distribution." value))))

(defun awrs-exact-acceptance-mass (distribution constraint)
  "Enumerate finite support as an independent diagnostic oracle."
  (validate-categorical-distribution distribution)
  (loop for (value . probability) in distribution
        when (funcall constraint value)
          sum (coerce probability 'double-float)))

(defun conditional-categorical-sample (distribution rejected state)
  (let* ((eligible
           (remove-if (lambda (entry)
                        (member (car entry) rejected :test #'equal))
                      distribution))
         (mass (loop for entry in eligible sum (cdr entry))))
    (unless (plusp mass)
      (error "No proposal mass remains after rejections ~S." rejected))
    (let ((target (* mass (awrs-random-unit state))) (cumulative 0.0d0))
      (dolist (entry eligible (caar (last eligible)))
        (incf cumulative (cdr entry))
        (when (< target cumulative) (return (car entry)))))))

(defstruct awrs-result value zhat exact-z telemetry)

(defun awrs-sample (distribution constraint
                    &key (state (make-awrs-random-state)) report-exact-z)
  "Run exact AWRS with one additional trace (L=1).

Return an accepted sample from P0 conditioned on CONSTRAINT and an unbiased
estimate ZHAT of its acceptance mass. Rejected outcomes are never proposed
again. Accepted outcomes remain available in the additional trace."
  (validate-categorical-distribution distribution)
  (let ((rejected '()) (trace-records '()) (total-rejections 0)
        (psi0 0.0d0) (accepted nil) (checks 0) (draws 0))
    (dotimes (trace-index 2)
      (let ((trace-rejections '()) (trace-accepted nil))
        (loop
          for value = (conditional-categorical-sample
                       distribution rejected state) do
            (incf draws)
            (incf checks)
            (if (funcall constraint value)
                (progn
                  (setf trace-accepted value)
                  (when (zerop trace-index) (setf accepted value))
                  (return))
                (progn
                  (push value rejected)
                  (push value trace-rejections)
                  (incf total-rejections)
                  (when (zerop trace-index)
                    (incf psi0 (categorical-probability value distribution))))))
        (push (list :trace trace-index
                    :rejections (nreverse trace-rejections)
                    :accepted trace-accepted)
              trace-records)))
    (let* ((zhat (/ (- 1.0d0 psi0) (1+ total-rejections)))
           (exact-z (and report-exact-z
                         (awrs-exact-acceptance-mass distribution constraint))))
      (make-awrs-result
       :value accepted :zhat zhat :exact-z exact-z
       :telemetry
       (list :algorithm :adaptive-weighted-rejection-sampling
             :additional-traces 1
             :conditional-draws draws
             :constraint-checks checks
             :total-rejections total-rejections
             :unique-rejections (nreverse (copy-list rejected))
             :psi0 psi0 :zhat zhat :exact-z exact-z
             :traces (nreverse trace-records))))))
