;;;; Dependency-free implementation of Lew et al.'s SMC steering algorithm.

(defstruct smc-random-state (value 1 :type integer))
(defun smc-make-random-state (seed)
  (unless (integerp seed) (error "The SMC seed must be an integer."))
  (make-smc-random-state :value (mod seed 4294967296)))
(defun smc-random-unit (state)
  (setf (smc-random-state-value state)
        (mod (+ (* 1664525 (smc-random-state-value state)) 1013904223)
             4294967296))
  (/ (+ 0.5d0 (smc-random-state-value state)) 4294967296.0d0))
(defun smc-random-integer (limit state)
  (unless (and (integerp limit) (plusp limit))
    (error "The random integer limit must be positive."))
  (min (1- limit) (floor (* limit (smc-random-unit state)))))

(defstruct smc-feature name column transformations)
(defstruct smc-particle
  (choices '()) (log-weight 0.0d0) score (log-potential 0.0d0)
  (step 0) parent)
(defstruct smc-search-result
  particles best-particle history evaluations cache-hits)

(defun smc-particle-weight (particle)
  (exp (smc-particle-log-weight particle)))
(defun smc-validate-feature (feature column-count)
  (unless (symbolp (smc-feature-name feature))
    (error "A feature name must be a symbol: ~S." feature))
  (unless (and (integerp (smc-feature-column feature))
               (<= 0 (smc-feature-column feature))
               (< (smc-feature-column feature) column-count))
    (error "Feature ~S has invalid column ~S for ~D input columns."
           (smc-feature-name feature) (smc-feature-column feature) column-count))
  (unless (and (consp (smc-feature-transformations feature))
               (every #'keywordp (smc-feature-transformations feature)))
    (error "Feature ~S needs a nonempty keyword transformation whitelist."
           (smc-feature-name feature)))
  feature)
(defun smc-choice-count (choices)
  (count-if (lambda (choice) (not (eq choice :exclude))) choices))
(defun smc-copy-particle (particle)
  (make-smc-particle :choices (copy-list (smc-particle-choices particle))
                     :log-weight (smc-particle-log-weight particle)
                     :score (smc-particle-score particle)
                     :log-potential (smc-particle-log-potential particle)
                     :step (smc-particle-step particle)
                     :parent (smc-particle-parent particle)))

(defun smc-logsumexp (numbers)
  (unless numbers (error "LOGSUMEXP requires at least one number."))
  (let ((maximum (reduce #'max numbers)))
    (if (= maximum most-negative-double-float)
        maximum
        (+ maximum
           (log (reduce #'+ numbers
                        :key (lambda (number) (exp (- number maximum)))))))))
(defun smc-normalized-weights (particles)
  (let* ((logs (mapcar #'smc-particle-log-weight particles))
         (total (smc-logsumexp logs)))
    (values (map 'vector (lambda (log-weight) (exp (- log-weight total))) logs)
            total)))
(defun smc-effective-sample-size-from-weights (weights)
  (/ 1.0d0 (loop for weight across weights sum (* weight weight))))

(defun smc-find-optimal-c (weights retained-count)
  "Solve SUM_i MIN(1,C*w_i)=RETAINED-COUNT for optimal resampling."
  (unless (<= 1 retained-count (length weights))
    (error "The retained count must be between 1 and the number of weights."))
  (let ((positive (loop for weight across weights when (plusp weight) collect weight)))
    (when (< (length positive) retained-count)
      (error "Optimal resampling needs at least ~D positive weights."
             retained-count))
    (labels ((inclusion-sum (c)
               (loop for weight across weights sum (min 1.0d0 (* c weight)))))
      (let ((low 0.0d0) (high (/ 1.0d0 (reduce #'min positive))))
        (dotimes (iteration 100)
          (declare (ignorable iteration))
          (let ((middle (/ (+ low high) 2.0d0)))
            (if (< (inclusion-sum middle) retained-count)
                (setf low middle)
                (setf high middle))))
        (/ (+ low high) 2.0d0)))))

(defun smc-optimal-resample-indices (weights retained-count state)
  "Fearnhead--Clifford optimal resampling used by Lew's SMC steering code."
  (let* ((count (length weights))
         (c (smc-find-optimal-c weights retained-count))
         (deterministic
           (loop for index below count
                 when (>= (* c (aref weights index)) 1.0d0) collect index))
         (stochastic
           (loop for index below count
                 when (< (* c (aref weights index)) 1.0d0) collect index))
         (needed (- retained-count (length deterministic))))
    (if (zerop needed)
        (values deterministic '() c)
        (let* ((stochastic-total
                 (loop for index in stochastic sum (aref weights index)))
               (interval (/ stochastic-total needed))
               (u (* interval (smc-random-unit state)))
               (selected '()))
          (dolist (index stochastic)
            (decf u (aref weights index))
            (when (<= u 0.0d0)
              (push index selected)
              (incf u interval)))
          (setf selected (nreverse selected))
          (unless (= (length selected) needed)
            (error "Optimal resampling selected ~D stochastic particles; expected ~D."
                   (length selected) needed))
          (values deterministic selected c)))))

(defun smc-legal-choices (feature included-count remaining-after minimum maximum)
  (cond
    ((>= included-count maximum) '(:exclude))
    ((< (+ included-count remaining-after) minimum)
     (copy-list (smc-feature-transformations feature)))
    (t (cons :exclude (copy-list (smc-feature-transformations feature))))))
(defun smc-propose-choice (legal state)
  "Uniform Q and matching declared prior P; return choice, log P, and log Q."
  (let* ((count (length legal))
         (choice (nth (smc-random-integer count state) legal))
         (log-probability (- (log (coerce count 'double-float)))))
    (values choice log-probability log-probability)))

(defun smc-run-search (features evaluator
                       &key (particle-count 4) (beam-factor 3)
                         (minimum-features 2) maximum-features
                         (beta 8.0d0) (seed 20260901))
  "Run Lew et al.'s SMC steering algorithm on feature decisions.

The sequential probabilistic program makes one decision per feature. Its final
target is PRIOR(CONFIGURATION) * EXP(BETA * SCORE(CONFIGURATION)), conditioned
on the declared feature-count bounds."
  (let* ((feature-count (length features))
         (maximum (or maximum-features feature-count))
         (state (smc-make-random-state seed))
         (cache (make-hash-table :test #'equal))
         (evaluations 0) (cache-hits 0) (best-particle nil) (history '())
         (particles (loop repeat particle-count collect (make-smc-particle))))
    (unless (and (plusp particle-count) (plusp beam-factor))
      (error "Particles and beam factor must be positive."))
    (unless (<= 1 minimum-features maximum feature-count)
      (error "Feature bounds must satisfy 1 <= minimum <= maximum <= ~D."
             feature-count))
    (labels ((evaluate (choices)
               (multiple-value-bind (value found) (gethash choices cache)
                 (if found
                     (progn (incf cache-hits) value)
                     (let ((score (funcall evaluator choices)))
                       (unless (realp score)
                         (error "The evaluator returned a non-number: ~S." score))
                       (incf evaluations)
                       (let ((number (coerce score 'double-float)))
                         (setf (gethash (copy-list choices) cache) number)
                         (when (or (null best-particle)
                                   (> number (smc-particle-score best-particle)))
                           (setf best-particle
                                 (make-smc-particle
                                  :choices (copy-list choices) :score number)))
                         number))))))
      (dotimes (step feature-count)
        (let* ((feature (nth step features))
               (remaining-after (- feature-count step 1))
               (n-total (* particle-count beam-factor))
               (children '()))
          (loop for parent in particles for parent-index from 0 do
            (dotimes (beam-index beam-factor)
              (declare (ignorable beam-index))
              (let* ((child (smc-copy-particle parent))
                     (legal (smc-legal-choices
                             feature (smc-choice-count (smc-particle-choices child))
                             remaining-after minimum-features maximum)))
                ;; Lew's published active-particle expansion correction.
                (incf (smc-particle-log-weight child)
                      (- (log (coerce n-total 'double-float))
                         (log (coerce particle-count 'double-float))
                         (log (coerce beam-factor 'double-float))))
                (multiple-value-bind (choice log-p log-q)
                    (smc-propose-choice legal state)
                  (setf (smc-particle-choices child)
                        (append (smc-particle-choices child) (list choice)))
                  (incf (smc-particle-log-weight child) (- log-p log-q)))
                (setf (smc-particle-step child) (1+ step)
                      (smc-particle-parent child) parent-index)
                (when (= (1+ step) feature-count)
                  (let* ((score (evaluate (smc-particle-choices child)))
                         (log-potential (* beta score)))
                    (incf (smc-particle-log-weight child)
                          (- log-potential (smc-particle-log-potential child)))
                    (setf (smc-particle-log-potential child) log-potential
                          (smc-particle-score child) score)))
                (push child children))))
          (setf children (nreverse children))
          (multiple-value-bind (normalized log-total)
              (smc-normalized-weights children)
            (let ((ess (smc-effective-sample-size-from-weights normalized)))
              (multiple-value-bind (deterministic stochastic c)
                  (smc-optimal-resample-indices normalized particle-count state)
                (setf particles
                      (append (mapcar (lambda (index) (nth index children))
                                      deterministic)
                              (mapcar (lambda (index) (nth index children))
                                      stochastic)))
                ;; Exact post-resampling corrections in Lew's reference code.
                (dolist (index deterministic)
                  (incf (smc-particle-log-weight (nth index children))
                        (- (log (coerce particle-count 'double-float))
                           (log (coerce n-total 'double-float)))))
                (dolist (index stochastic)
                  (setf (smc-particle-log-weight (nth index children))
                        (+ log-total (- (log c))
                           (log (coerce particle-count 'double-float))
                           (- (log (coerce n-total 'double-float))))))
                (push (list :step (1+ step)
                            :feature (smc-feature-name feature)
                            :child-count n-total
                            :effective-sample-size ess
                            :deterministic-count (length deterministic)
                            :stochastic-count (length stochastic)
                            :c c)
                      history))))))
      (setf particles (sort particles #'>
                            :key (lambda (particle)
                                   (or (smc-particle-score particle)
                                       most-negative-double-float))))
      (make-smc-search-result :particles particles :best-particle best-particle
                              :history (nreverse history)
                              :evaluations evaluations :cache-hits cache-hits))))
