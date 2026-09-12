;;;; Sequential Monte Carlo with properly weighted AWRS proposals.

(unless (find-package :awrs-smc)
  (load (merge-pathnames "awrs.lisp"
                         (make-pathname :name nil :type nil
                                        :defaults *load-truename*))))

(in-package :awrs-smc)

(defstruct awrs-particle (values '()) (weight 1.0d0) (active-p t) (calls '()))
(defstruct awrs-smc-result particles selected normalizer-estimate telemetry)

(defun particle-population-weight (particles)
  (loop for particle in particles sum (awrs-particle-weight particle)))

(defun particle-effective-sample-size (particles)
  (unless particles (error "ESS requires at least one particle."))
  (let ((maximum (reduce #'max particles :key #'awrs-particle-weight)))
    (unless (plusp maximum) (error "All particle weights are zero."))
    (let* ((scaled (mapcar (lambda (particle)
                             (/ (awrs-particle-weight particle) maximum))
                           particles))
           (sum (reduce #'+ scaled))
           (squares (reduce #'+ scaled :key (lambda (x) (* x x)))))
      (/ (* sum sum) squares))))

(defun weighted-particle-index (particles state)
  (let* ((total (particle-population-weight particles))
         (target (* total (awrs-random-unit state)))
         (cumulative 0.0d0))
    (loop for particle in particles for index from 0 do
      (incf cumulative (awrs-particle-weight particle))
      (when (< target cumulative) (return index))
      finally (return (1- (length particles))))))

(defun copy-awrs-particle-for-resampling (particle new-weight)
  (make-awrs-particle :values (copy-list (awrs-particle-values particle))
                      :weight new-weight
                      :active-p (awrs-particle-active-p particle)
                      :calls (copy-tree (awrs-particle-calls particle))))

(defun multinomial-resample (particles state)
  "Algorithm 2 resampling: categorical ancestors and post-weight W/M."
  (let* ((count (length particles))
         (total (particle-population-weight particles))
         (new-weight (/ total count)))
    (loop repeat count
          for index = (weighted-particle-index particles state)
          collect (copy-awrs-particle-for-resampling
                   (nth index particles) new-weight))))

(defun systematic-resample (particles state)
  "Systematic resampling (Kitagawa 1996): one shared random offset and M
evenly spaced draws along the cumulative weight, instead of M independent
draws. Same marginal selection probability w/W and the same post-weight W/M
as MULTINOMIAL-RESAMPLE, but much lower variance in realized copy counts for
the same particle count -- a standard SMC variance-reduction technique.

This is NOT part of the source paper's Algorithm 2 (which specifies plain
multinomial resampling; see MULTINOMIAL-RESAMPLE above); it is offered here
as an opt-in. Pass :RESAMPLING-METHOD :SYSTEMATIC to RUN-AWRS-SMC to use it."
  (let* ((count (length particles))
         (particle-vector (coerce particles 'vector))
         (weight-vector (map 'vector #'awrs-particle-weight particle-vector))
         (total (reduce #'+ weight-vector))
         (new-weight (/ total count))
         (offset (* new-weight (awrs-random-unit state)))
         (cumulative (aref weight-vector 0))
         (cursor 0))
    (loop for m below count
          for target = (+ offset (* m new-weight))
          do (loop while (and (< cumulative target) (< cursor (1- count)))
                   do (incf cursor) (incf cumulative (aref weight-vector cursor)))
          collect (copy-awrs-particle-for-resampling
                   (aref particle-vector cursor) new-weight))))

(defun run-awrs-smc (proposal-function constraint-function
                     &key (particle-count 5) (resampling-threshold 0.5d0)
                       (end-marker :eos) (maximum-steps 100)
                       (seed 20260902) report-exact-z
                       terminal-potential-function
                       (resampling-method :multinomial))
  "Run Algorithm 2 using AWRS as the properly weighted token proposal.

PROPOSAL-FUNCTION receives a prefix and returns a normalized categorical alist.
CONSTRAINT-FUNCTION receives a prefix and candidate value. END-MARKER completes
a particle and is not included in its returned value sequence.

Each proposal step runs AWRS-SAMPLE as-is -- one accepted trace plus exactly
one continuation trace, with no budget/ADDITIONAL-TRACES knob; see
AWRS-SAMPLE's docstring for why. RESAMPLING-METHOD is :MULTINOMIAL
(Algorithm 2's own method, and the default) or :SYSTEMATIC (a lower-variance
opt-in; see SYSTEMATIC-RESAMPLE)."
  (unless (and (integerp particle-count) (plusp particle-count))
    (error "PARTICLE-COUNT must be positive."))
  (unless (and (realp resampling-threshold)
               (< 0 resampling-threshold) (<= resampling-threshold 1))
    (error "RESAMPLING-THRESHOLD must be in (0,1]."))
  (unless (member resampling-method '(:multinomial :systematic))
    (error "RESAMPLING-METHOD must be :MULTINOMIAL or :SYSTEMATIC, got ~S."
           resampling-method))
  (let* ((state (make-awrs-random-state seed))
         (particles (loop repeat particle-count collect (make-awrs-particle)))
         (history '()) (iterations 0) (interactions 0) (resampling-count 0)
         (awrs-draws 0) (constraint-checks 0) (rejections 0)
         (terminal-evaluations 0))
    (loop while (some #'awrs-particle-active-p particles) do
      (when (>= iterations maximum-steps)
        (error "AWRS-SMC exceeded MAXIMUM-STEPS=~D." maximum-steps))
      (incf iterations)
      (let ((active-before (count-if #'awrs-particle-active-p particles))
            (iteration-calls '()))
        (dolist (particle particles)
          (when (awrs-particle-active-p particle)
            (incf interactions)
            (let* ((prefix (awrs-particle-values particle))
                   (distribution (funcall proposal-function prefix))
                   (constraint (lambda (value)
                                 (funcall constraint-function prefix value)))
                   (result (awrs-sample
                            distribution constraint :state state
                            :report-exact-z report-exact-z))
                   (token (awrs-result-value result))
                   (call (awrs-result-telemetry result)))
              (setf (awrs-particle-weight particle)
                    (* (awrs-particle-weight particle) (awrs-result-zhat result)))
              (if (equal token end-marker)
                  (progn
                    (setf (awrs-particle-active-p particle) nil)
                    (when terminal-potential-function
                      (let ((potential
                              (funcall terminal-potential-function prefix)))
                        (unless (and (realp potential) (plusp potential))
                          (error "Terminal potential must be positive, got ~S."
                                 potential))
                        (setf (awrs-particle-weight particle)
                              (* (awrs-particle-weight particle)
                                 (coerce potential 'double-float)))
                        (incf terminal-evaluations))))
                  (setf (awrs-particle-values particle)
                        (append prefix (list token))))
              (push call (awrs-particle-calls particle))
              (push call iteration-calls)
              (incf awrs-draws (getf call :conditional-draws))
              (incf constraint-checks (getf call :constraint-checks))
              (incf rejections (getf call :total-rejections)))))
        (let* ((ess-before (particle-effective-sample-size particles))
               (total-before (particle-population-weight particles))
               (resampled-p (< ess-before
                               (* resampling-threshold particle-count))))
          (when resampled-p
            (setf particles (ecase resampling-method
                              (:multinomial (multinomial-resample particles state))
                              (:systematic (systematic-resample particles state))))
            (incf resampling-count))
          (push (list :iteration iterations :active-before active-before
                      :particle-interactions active-before
                      :population-weight-before total-before
                      :ess-before ess-before :resampled resampled-p
                      :ess-after (particle-effective-sample-size particles)
                      :awrs-calls (nreverse iteration-calls))
                history))))
    (let* ((normalizer (/ (particle-population-weight particles) particle-count))
           ;; SELECTED is a stochastic draw from the final weighted particle
           ;; population, proportional to weight -- the literal SMC output
           ;; (Algorithm 1's implicit posterior sample). Callers wanting one
           ;; deterministic "best" particle instead (as every caller in this
           ;; codebase currently does) should re-rank PARTICLES by their own
           ;; quality metric and take the argmax, not use this field.
           (selected-index (weighted-particle-index particles state))
           (selected (nth selected-index particles)))
      (make-awrs-smc-result
       :particles particles :selected selected :normalizer-estimate normalizer
       :telemetry
       (list :algorithm :smc-with-properly-weighted-awrs-proposal
             :particle-count particle-count
             :resampling-threshold resampling-threshold
             :resampling-method resampling-method
             :seed seed :iterations iterations :interactions interactions
             :resampling-count resampling-count
             :awrs-conditional-draws awrs-draws
             :constraint-checks constraint-checks
             :rejections rejections
             :terminal-evaluations terminal-evaluations
             :final-ess (particle-effective-sample-size particles)
             :normalizer-estimate normalizer
             :selected-particle selected-index
             :history (nreverse history))))))
