;;;; CINEMA-OT adaptation for SF-VIPN solar-flux counterfactuals.
;;;; ANSI Common Lisp for SBCL, no external dependencies.
;;;;
;;;; Faithful transferable core: treatment-dependence filtering, squared
;;;; confounder cost, entropy-regularized transport, Sinkhorn--Knopp marginal
;;;; scaling, and barycentric counterfactual effects.  Physical cyclic modules
;;;; replace gene-expression ICA until the ROCSAT multivariate experiment.

(defparameter *fejer-cinema-low-flux* 100.0)
(defparameter *fejer-cinema-high-flux* 140.0)
(defparameter *fejer-cinema-smoothness* 0.08)
(defparameter *fejer-cinema-iterations* 250)
(defparameter *fejer-cinema-tolerance* 0.00001)
(defparameter *fejer-cinema-strength* 0.10)
(defparameter *fejer-cinema-bin-shrinkage* 10.0)
(defparameter *fejer-cinema-dependence-threshold* 0.75)
(defparameter *fejer-cinema-minimum-support-ratio* 0.20)

(defun fejer-cinema-absolute (value)
  (if (< value 0.0) (- value) value))

(defun fejer-cinema-square (value) (* value value))

(defun fejer-cinema-exp-small (value)
  (let ((term 1.0) (sum 1.0) (index 1))
    (loop
      (when (> index 24) (return sum))
      (setf term (/ (* term value) index))
      (setf sum (+ sum term))
      (setf index (1+ index)))))

(defun fejer-cinema-exp (value)
  (cond ((< value -60.0) 0.0)
        ((> value 60.0) (fejer-cinema-exp 60.0))
        ((< value -1.0)
         (let ((half (fejer-cinema-exp (/ value 2.0)))) (* half half)))
        ((> value 1.0)
         (let ((half (fejer-cinema-exp (/ value 2.0)))) (* half half)))
        (t (fejer-cinema-exp-small value))))

(defun fejer-cinema-circular-distance (left right period)
  (let ((distance (fejer-cinema-absolute (- left right))))
    (if (> distance (/ period 2.0)) (- period distance) distance)))

(defun fejer-cinema-high-p (observation)
  (>= (fejer-sf-vipn-get observation :f107) *fejer-cinema-high-flux*))

(defun fejer-cinema-low-p (observation)
  (<= (fejer-sf-vipn-get observation :f107) *fejer-cinema-low-flux*))

(defun fejer-cinema-select (observations predicate)
  (let ((result '()))
    (dolist (observation observations (nreverse result))
      (when (funcall predicate observation) (push observation result)))))

(defun fejer-cinema-treatment (observation)
  (if (fejer-cinema-high-p observation) 1 0))

(defun fejer-cinema-feature (observation index)
  (cond ((= index 0)
         (/ (fejer-sf-vipn-get observation :local-time) 24.0))
        ((= index 1) (/ (fejer-sf-vipn-get observation :day) 365.0))
        ((= index 2) (/ (fejer-sf-vipn-get observation :sf99) 50.0))
        ((= index 3)
         (/ (fejer-sf-vipn-get observation :measurement-error) 20.0))
        (t (/ (fejer-sf-vipn-residual observation) 50.0))))

(defun fejer-cinema-insert-by-feature (observation ordered feature-index)
  (cond ((null ordered) (list observation))
        ((< (fejer-cinema-feature observation feature-index)
            (fejer-cinema-feature (car ordered) feature-index))
         (cons observation ordered))
        (t (cons (car ordered)
                 (fejer-cinema-insert-by-feature
                  observation (cdr ordered) feature-index)))))

(defun fejer-cinema-order-by-feature (observations feature-index)
  (let ((ordered '()))
    (dolist (observation observations ordered)
      (setf ordered
            (fejer-cinema-insert-by-feature observation ordered feature-index)))))

(defun fejer-cinema-treatment-count (observations treatment)
  (let ((count 0))
    (dolist (observation observations count)
      (when (= treatment (fejer-cinema-treatment observation))
        (setf count (1+ count))))))

(defun fejer-cinema-chatterjee-xi (observations feature-index)
  (let* ((count (length observations))
         (zero-count (fejer-cinema-treatment-count observations 0))
         (one-count (- count zero-count)))
    (if (or (< count 3) (zerop zero-count) (zerop one-count))
        0.0
        (let ((ordered (fejer-cinema-order-by-feature observations feature-index))
              (numerator 0.0) (denominator 0.0) (previous nil))
          (dolist (observation ordered)
            (let* ((treatment (fejer-cinema-treatment observation))
                   (rank (if (zerop treatment) zero-count count))
                   (upper (if (zerop treatment) count one-count)))
              (when previous
                (setf numerator
                      (+ numerator (fejer-cinema-absolute (- rank previous)))))
              (setf denominator (+ denominator (* upper (- count upper))))
              (setf previous rank)))
          (let ((raw (if (zerop denominator) 0.0
                         (- 1.0 (/ (* count numerator)
                                   (* 2.0 denominator))))))
            (cond ((< raw 0.0) 0.0) ((> raw 1.0) 1.0) (t raw)))))))

(defun fejer-cinema-retained-features (training)
  (setf training training)
  '(0 1 2 3))

(defun fejer-cinema-cost (high low retained)
  (let ((sum 0.0))
    (dolist (index retained sum)
      (let ((distance
              (cond ((= index 0)
                     (/ (fejer-cinema-circular-distance
                         (fejer-sf-vipn-get high :local-time)
                         (fejer-sf-vipn-get low :local-time) 24.0) 12.0))
                    ((= index 1)
                     (/ (fejer-cinema-circular-distance
                         (fejer-sf-vipn-get high :day)
                         (fejer-sf-vipn-get low :day) 365.0) 182.5))
                    (t (- (fejer-cinema-feature high index)
                          (fejer-cinema-feature low index))))))
        (setf sum (+ sum (fejer-cinema-square distance)))))))

(defun fejer-cinema-kernel (highs lows retained)
  (let* ((rows (length highs)) (columns (length lows))
         (matrix (make-array (list rows columns) :initial-element 0.0)))
    (dotimes (row rows matrix)
      (dotimes (column columns)
        (let ((cost (fejer-cinema-cost (elt highs row) (elt lows column)
                                       retained)))
          (setf (aref matrix row column)
                (- (/ cost *fejer-cinema-smoothness*))))))))

(defun fejer-cinema-vector (count value)
  (make-array count :initial-element value))

(defun fejer-cinema-log-add (left right)
  (if (> left right)
      (+ left (log (+ 1.0 (exp (- right left)))))
      (+ right (log (+ 1.0 (exp (- left right)))))))

(defun fejer-cinema-row-denominator (kernel row right columns)
  (let ((sum nil))
    (dotimes (column columns sum)
      (let ((value (+ (aref kernel row column) (aref right column))))
        (setf sum (if sum (fejer-cinema-log-add sum value) value))))))

(defun fejer-cinema-column-denominator (kernel column left rows)
  (let ((sum nil))
    (dotimes (row rows sum)
      (let ((value (+ (aref left row) (aref kernel row column))))
        (setf sum (if sum (fejer-cinema-log-add sum value) value))))))

(defun fejer-cinema-vector-change (left right count)
  (let ((sum 0.0))
    (dotimes (index count sum)
      (setf sum (+ sum (fejer-cinema-absolute
                        (- (aref left index) (aref right index))))))))

(defun fejer-cinema-sinkhorn (kernel rows columns)
  (let ((left (fejer-cinema-vector rows 0.0))
        (right (fejer-cinema-vector columns 0.0))
        (row-mass (- (log rows))) (column-mass (- (log columns)))
        (iteration 0) (change 1.0))
    (loop
      (when (or (= iteration *fejer-cinema-iterations*)
                (< change *fejer-cinema-tolerance*))
        (return (list left right iteration change)))
      (let ((next-left (fejer-cinema-vector rows 0.0)))
        (dotimes (row rows)
          (setf (aref next-left row)
                (- row-mass
                   (fejer-cinema-row-denominator kernel row right columns))))
        (setf change (fejer-cinema-vector-change left next-left rows))
        (setf left next-left))
      (let ((next-right (fejer-cinema-vector columns 0.0)))
        (dotimes (column columns)
          (setf (aref next-right column)
                (- column-mass
                   (fejer-cinema-column-denominator kernel column left rows))))
        (setf change (+ change
                        (fejer-cinema-vector-change right next-right columns)))
        (setf right next-right))
      (setf iteration (1+ iteration)))))

(defun fejer-cinema-plan-value (kernel scaling row column)
  (exp (+ (aref (car scaling) row) (aref kernel row column)
          (aref (car (cdr scaling)) column))))

(defun fejer-cinema-row-diagnostic (kernel scaling row columns)
  (let ((mass 0.0) (square-sum 0.0) (maximum 0.0) (entropy 0.0))
    (dotimes (column columns)
      (setf mass (+ mass (fejer-cinema-plan-value
                          kernel scaling row column))))
    (dotimes (column columns)
      (let ((share (if (zerop mass) 0.0
                       (/ (fejer-cinema-plan-value kernel scaling row column)
                          mass))))
        (setf square-sum (+ square-sum (* share share)))
        (when (> share 0.0)
          (setf entropy (- entropy (* share (log share)))))
        (when (> share maximum) (setf maximum share))))
    (list :effective-matches (if (zerop square-sum) 0.0 (/ 1.0 square-sum))
          :maximum-share maximum :entropy-nats entropy
          :entropy-effective-matches (exp entropy))))

(defun fejer-cinema-high-effect (kernel scaling highs lows row)
  (let ((mass 0.0) (counterfactual 0.0)
        (column 0) (low-rest lows))
    (loop
      (when (null low-rest) (return nil))
      (let ((weight (fejer-cinema-plan-value kernel scaling row column)))
        (setf mass (+ mass weight))
        (setf counterfactual
              (+ counterfactual
                 (* weight (fejer-sf-vipn-residual (car low-rest))))))
      (setf column (1+ column))
      (setf low-rest (cdr low-rest)))
    (if (zerop mass) 0.0
        (- (fejer-sf-vipn-residual (elt highs row))
           (/ counterfactual mass)))))

(defun fejer-cinema-effects (training)
  (let* ((highs (fejer-cinema-select training #'fejer-cinema-high-p))
         (lows (fejer-cinema-select training #'fejer-cinema-low-p)))
    (if (or (null highs) (null lows)
            (< (/ (if (< (length highs) (length lows))
                      (length highs) (length lows))
                  (if (> (length highs) (length lows))
                      (length highs) (length lows)))
               *fejer-cinema-minimum-support-ratio*))
        (list :effects '() :high-count (length highs) :low-count (length lows)
              :retained '() :iterations 0 :change 0.0)
        (let* ((retained (fejer-cinema-retained-features training))
               (kernel (fejer-cinema-kernel highs lows retained))
               (scaling (fejer-cinema-sinkhorn
                         kernel (length highs) (length lows)))
               (effects '()) (effective-sum 0.0) (maximum-sum 0.0)
               (entropy-sum 0.0) (entropy-effective-sum 0.0)
               (dominated-count 0))
          (dotimes (row (length highs))
            (let* ((diagnostic (fejer-cinema-row-diagnostic
                                kernel scaling row (length lows)))
                   (effective (fejer-sf-vipn-get
                               diagnostic :effective-matches)))
              (setf effective-sum (+ effective-sum effective))
              (setf maximum-sum
                    (+ maximum-sum
                       (fejer-sf-vipn-get diagnostic :maximum-share)))
              (setf entropy-sum
                    (+ entropy-sum
                       (fejer-sf-vipn-get diagnostic :entropy-nats)))
              (setf entropy-effective-sum
                    (+ entropy-effective-sum
                       (fejer-sf-vipn-get
                        diagnostic :entropy-effective-matches)))
              (when (<= effective 2.0)
                (setf dominated-count (1+ dominated-count)))
              (push (list :bin (fejer-sf-vipn-bin (elt highs row))
                          :effect (fejer-cinema-high-effect
                                   kernel scaling highs lows row))
                    effects)))
          (list :effects (nreverse effects) :high-count (length highs)
                :low-count (length lows) :retained retained
                :iterations (elt scaling 2) :change (elt scaling 3)
                :mean-effective-matches (/ effective-sum (length highs))
                :mean-maximum-share (/ maximum-sum (length highs))
                :mean-entropy-nats (/ entropy-sum (length highs))
                :mean-entropy-effective-matches
                (/ entropy-effective-sum (length highs))
                :rows-effective-at-most-two dominated-count)))))

(defun fejer-cinema-mean-effect (effects)
  (let ((sum 0.0) (count 0))
    (dolist (effect effects (if (zerop count) 0.0 (/ sum count)))
      (setf sum (+ sum (fejer-sf-vipn-get effect :effect)))
      (setf count (1+ count)))))

(defun fejer-cinema-bin-effect (effects bin)
  (let ((sum 0.0) (count 0) (overall (fejer-cinema-mean-effect effects)))
    (dolist (effect effects)
      (when (= bin (fejer-sf-vipn-get effect :bin))
        (setf sum (+ sum (fejer-sf-vipn-get effect :effect)))
        (setf count (1+ count))))
    (/ (+ sum (* *fejer-cinema-bin-shrinkage* overall))
       (+ count *fejer-cinema-bin-shrinkage*))))

(defun fejer-cinema-flux-weight (flux)
  (cond ((<= flux *fejer-cinema-low-flux*) -0.5)
        ((>= flux *fejer-cinema-high-flux*) 0.5)
        (t (- (/ (- flux *fejer-cinema-low-flux*)
                 (- *fejer-cinema-high-flux* *fejer-cinema-low-flux*))
              0.5))))

(defun fejer-cinema-correction (effects observation)
  (* *fejer-cinema-strength*
     (fejer-cinema-flux-weight (fejer-sf-vipn-get observation :f107))
     (fejer-cinema-bin-effect effects (fejer-sf-vipn-bin observation))))

(defun fejer-cinema-predict-event (training test)
  (let* ((model (fejer-cinema-effects training))
         (effects (fejer-sf-vipn-get model :effects)) (result '()))
    (dolist (observation test (list (nreverse result) model))
      (push (append observation
                    (list :sf-vipn-cinema
                          (+ (fejer-sf-vipn-get observation :sf99)
                             (fejer-cinema-correction effects observation))))
            result))))

(defun fejer-cinema-score (predictions)
  (let ((sf99-sum 0.0) (cinema-sum 0.0) (count 0))
    (dolist (prediction predictions)
      (let ((observed (fejer-sf-vipn-get prediction :observed)))
        (setf sf99-sum (+ sf99-sum (fejer-cinema-absolute
                                    (- observed (fejer-sf-vipn-get
                                                 prediction :sf99)))))
        (setf cinema-sum (+ cinema-sum (fejer-cinema-absolute
                                       (- observed (fejer-sf-vipn-get
                                                    prediction
                                                    :sf-vipn-cinema)))))
        (setf count (1+ count))))
    (list :count count
          :sf99-mae (if (zerop count) 0.0 (/ sf99-sum count))
          :cinema-mae (if (zerop count) 0.0 (/ cinema-sum count)))))

(defun fejer-cinema-fold (observations event)
  (let* ((training (fejer-surrogate-excluding observations event))
         (test (fejer-surrogate-only observations event))
         (prediction-and-model (fejer-cinema-predict-event training test))
         (predictions (car prediction-and-model))
         (model (car (cdr prediction-and-model))))
    (append (list :event event
                  :high-count (fejer-sf-vipn-get model :high-count)
                  :low-count (fejer-sf-vipn-get model :low-count)
                  :retained (fejer-sf-vipn-get model :retained)
                  :iterations (fejer-sf-vipn-get model :iterations)
                  :change (fejer-sf-vipn-get model :change)
                  :mean-effective-matches
                  (fejer-sf-vipn-get model :mean-effective-matches)
                  :mean-maximum-share
                  (fejer-sf-vipn-get model :mean-maximum-share)
                  :mean-entropy-nats
                  (fejer-sf-vipn-get model :mean-entropy-nats)
                  :mean-entropy-effective-matches
                  (fejer-sf-vipn-get model :mean-entropy-effective-matches)
                  :rows-effective-at-most-two
                  (fejer-sf-vipn-get model :rows-effective-at-most-two))
            (fejer-cinema-score predictions))))

(defun fejer-cinema-evaluate (observations events)
  (let ((folds '()) (sf99-sum 0.0) (cinema-sum 0.0) (count 0)
        (effective-sum 0.0) (maximum-sum 0.0) (entropy-sum 0.0)
        (entropy-effective-sum 0.0) (diagnostic-rows 0)
        (dominated-count 0))
    (dolist (event events)
      (let* ((fold (fejer-cinema-fold observations event))
             (fold-count (fejer-sf-vipn-get fold :count)))
        (push fold folds)
        (setf sf99-sum (+ sf99-sum (* fold-count
                                      (fejer-sf-vipn-get fold :sf99-mae))))
        (setf cinema-sum (+ cinema-sum (* fold-count
                                          (fejer-sf-vipn-get fold
                                                               :cinema-mae))))
        (let ((high-count (fejer-sf-vipn-get fold :high-count)))
          (when (fejer-sf-vipn-get fold :mean-effective-matches)
            (setf effective-sum
                  (+ effective-sum
                     (* high-count (fejer-sf-vipn-get
                                    fold :mean-effective-matches))))
            (setf maximum-sum
                  (+ maximum-sum
                     (* high-count (fejer-sf-vipn-get
                                    fold :mean-maximum-share))))
            (setf entropy-sum
                  (+ entropy-sum
                     (* high-count (fejer-sf-vipn-get
                                    fold :mean-entropy-nats))))
            (setf entropy-effective-sum
                  (+ entropy-effective-sum
                     (* high-count (fejer-sf-vipn-get
                                    fold :mean-entropy-effective-matches))))
            (setf diagnostic-rows (+ diagnostic-rows high-count))
            (setf dominated-count
                  (+ dominated-count (fejer-sf-vipn-get
                                      fold :rows-effective-at-most-two)))))
        (setf count (+ count fold-count))))
    (let ((sf99-mae (if (zerop count) 0.0 (/ sf99-sum count)))
          (cinema-mae (if (zerop count) 0.0 (/ cinema-sum count))))
      (list :model :cinema-ot-sf-vipn :records count :folds (nreverse folds)
            :sf99-mae sf99-mae :cinema-mae cinema-mae
            :relative-to-sf99-percent
            (if (zerop sf99-mae) 0.0
                (* 100.0 (/ (- cinema-mae sf99-mae) sf99-mae)))
            :mean-effective-matches
            (if (zerop diagnostic-rows) 0.0
                (/ effective-sum diagnostic-rows))
            :mean-maximum-share
            (if (zerop diagnostic-rows) 0.0
                (/ maximum-sum diagnostic-rows))
            :mean-entropy-nats
            (if (zerop diagnostic-rows) 0.0
                (/ entropy-sum diagnostic-rows))
            :mean-entropy-effective-matches
            (if (zerop diagnostic-rows) 0.0
                (/ entropy-effective-sum diagnostic-rows))
            :percent-rows-effective-at-most-two
            (if (zerop diagnostic-rows) 0.0
                (* 100.0 (/ dominated-count diagnostic-rows)))
            :first-counterfactual-mae 8.014639
            :difference-from-first-counterfactual
            (- cinema-mae 8.014639)))))
