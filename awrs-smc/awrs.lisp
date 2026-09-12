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
  (value 0 :type (unsigned-byte 64)))

(defparameter +awrs-splitmix64-golden-gamma+ #x9E3779B97F4A7C15
  "SplitMix64's golden-ratio state increment (Steele, Lea & Flood 2014).")

(defun awrs-splitmix64-mix (z)
  "SplitMix64's 64-bit output-mixing/finalizer function."
  (declare (type (unsigned-byte 64) z))
  (setf z (logand (* (logxor z (ash z -30)) #xBF58476D1CE4E5B9)
                  #xFFFFFFFFFFFFFFFF))
  (setf z (logand (* (logxor z (ash z -27)) #x94D049BB133111EB)
                  #xFFFFFFFFFFFFFFFF))
  (logxor z (ash z -31)))

(defun make-awrs-random-state (&optional (seed 20260902))
  "Seed a SplitMix64 generator (Steele, Lea & Flood 2014).

This replaces an earlier 32-bit linear congruential generator (period 2^32,
well-known poor spectral quality and low-order-bit correlations). SplitMix64
has a 2^64 period and passes standard statistical test suites (PractRand,
TestU01 SmallCrush/Crush); the call signature and every caller are unchanged."
  (unless (integerp seed) (error "The random seed must be an integer."))
  (%make-awrs-random-state
   (awrs-splitmix64-mix (logand (mod seed (ash 1 64)) #xFFFFFFFFFFFFFFFF))))

(defun awrs-random-unit (state)
  "Return a uniform double-float in [0, 1) and advance STATE by one step."
  (let ((next (logand (+ (awrs-random-state-value state)
                         +awrs-splitmix64-golden-gamma+)
                      #xFFFFFFFFFFFFFFFF)))
    (setf (awrs-random-state-value state) next)
    (/ (coerce (ash (awrs-splitmix64-mix next) -11) 'double-float)
       9007199254740992.0d0)))

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
  "Run AWRS: Definition 2 of Lipkin et al. (2025), exactly as stated there --
one trace that finds the accepted value, plus exactly one continuation trace.

Return an accepted sample from P0 conditioned on CONSTRAINT and an unbiased
estimate ZHAT of its acceptance mass, ZHAT := (1-PSI0)/(n0+n1+1). Rejected
outcomes are never proposed again. The accepted outcome remains available in
the continuation trace.

There is deliberately no budget/ADDITIONAL-TRACES parameter here, unlike
Definition 1's WRS (which the source paper does prove for a general budget
L, via ZHAT := L/(n+L)). An earlier version of this codebase added one to
AWRS anyway, by analogy with WRS; that analogy is wrong. WRS's L/(n+L) is
unbiased because each of its L+1 loops resamples from the full, unmodified
P0, so its total rejection count is an exact sum of L+1 i.i.d. Geometric(Z)
draws. AWRS's loops instead share one growing, permanently excluded
rejection set, so loops beyond the first are not i.i.d. with the first, and
the same style of formula is provably biased for L>1 -- e.g. two outcomes
of probability 1/2 each give E[ZHAT]=13/24 for L=2, not 1/2. No correct
general-L AWRS estimator is known here or stated in the source paper (its
Proposition 3 covers only this exact single-continuation-trace case). Do not
re-add a budget parameter without an actual proof to go with it."
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
    (let* ((zhat (/ (- 1.0d0 psi0) (+ total-rejections 1)))
           (exact-z (and report-exact-z
                         (awrs-exact-acceptance-mass distribution constraint))))
      (make-awrs-result
       :value accepted :zhat zhat :exact-z exact-z
       :telemetry
       (list :algorithm :adaptive-weighted-rejection-sampling
             :conditional-draws draws
             :constraint-checks checks
             :total-rejections total-rejections
             :unique-rejections (nreverse (copy-list rejected))
             :psi0 psi0 :zhat zhat :exact-z exact-z
             :traces (nreverse trace-records))))))
