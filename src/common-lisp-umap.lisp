;;;; Deterministic dependency-free UMAP for dense Common Lisp arrays.
;;;;
;;;; This follows the algorithm described by McInnes, Healy, and Melville and
;;;; the Apache-2.0 PAIR-code/umap-js implementation: exact k-nearest
;;;; neighbors, smooth k-NN distances, fuzzy-set union, and
;;;; attractive/repulsive stochastic optimization.  It is an independent ANSI
;;;; Common Lisp implementation and does not execute JavaScript.

(defstruct cl-umap-result
  input
  standardized-input
  neighbor-indices
  neighbor-distances
  sigmas
  rhos
  fuzzy-graph
  coordinates
  neighbors
  minimum-distance
  epochs
  seed
  a
  b)

(defstruct (cl-umap-rng (:constructor make-cl-umap-rng (state))) state)

(defun cl-umap-random-unit (rng)
  (let ((x (cl-umap-rng-state rng)))
    (setf x (logxor x (ash x 13)))
    (setf x (logxor x (ash x -17)))
    (setf x (logxor x (ash x 5)))
    (setf x (logand x #xffffffff))
    (setf (cl-umap-rng-state rng) x)
    (/ (coerce x 'double-float) 4294967296.0d0)))

(defun cl-umap-random-integer (limit rng)
  (min (1- limit) (floor (* limit (cl-umap-random-unit rng)))))

(defun cl-umap-check-input (input)
  (unless (and (arrayp input) (= (array-rank input) 2))
    (error "UMAP input must be a rank-two array."))
  (unless (> (array-dimension input 0) 2)
    (error "UMAP requires at least three observations."))
  (unless (> (array-dimension input 1) 0)
    (error "UMAP requires at least one feature."))
  (dotimes (row (array-dimension input 0))
    (dotimes (column (array-dimension input 1))
      (unless (realp (aref input row column))
        (error "UMAP input contains a non-real value at (~D, ~D)."
               row column))))
  input)

(defun cl-umap-standardize (input)
  (cl-umap-check-input input)
  (let* ((rows (array-dimension input 0))
         (columns (array-dimension input 1))
         (result (make-array (list rows columns)
                             :element-type 'double-float))
         (means (make-array columns :element-type 'double-float))
         (scales (make-array columns :element-type 'double-float)))
    (dotimes (column columns)
      (let ((mean (/ (loop for row below rows
                           sum (coerce (aref input row column) 'double-float))
                     rows)))
        (setf (aref means column) mean)
        (let ((scale
                (sqrt
                 (/ (loop for row below rows
                          for delta = (- (coerce (aref input row column)
                                                 'double-float)
                                         mean)
                          sum (* delta delta))
                    (max 1 (1- rows))))))
          (setf (aref scales column)
                (if (zerop scale) 1.0d0 scale)))))
    (dotimes (row rows result)
      (dotimes (column columns)
        (setf (aref result row column)
              (/ (- (coerce (aref input row column) 'double-float)
                    (aref means column))
                 (aref scales column)))))))

(defun cl-umap-distance (input first second)
  (sqrt
   (loop for column below (array-dimension input 1)
         for delta = (- (aref input first column)
                        (aref input second column))
         sum (* delta delta))))

(defun cl-umap-exact-neighbors (input neighbors)
  (let* ((count (array-dimension input 0))
         (k (min neighbors count))
         (indices (make-array (list count k) :element-type 'fixnum))
         (distances (make-array (list count k)
                                :element-type 'double-float)))
    (dotimes (row count)
      (let ((pairs
              (loop for other below count
                    collect (cons (cl-umap-distance input row other) other))))
        (setf pairs
              (sort pairs
                    (lambda (left right)
                      (or (< (car left) (car right))
                          (and (= (car left) (car right))
                               (< (cdr left) (cdr right)))))))
        (dotimes (column k)
          (setf (aref distances row column) (car (nth column pairs))
                (aref indices row column) (cdr (nth column pairs))))))
    (values indices distances)))

(defun cl-umap-row-mean (array row)
  (/ (loop for column below (array-dimension array 1)
           sum (aref array row column))
     (array-dimension array 1)))

(defun cl-umap-smooth-distances (distances neighbors)
  (let* ((rows (array-dimension distances 0))
         (columns (array-dimension distances 1))
         (target (/ (log (coerce neighbors 'double-float)) (log 2.0d0)))
         (sigmas (make-array rows :element-type 'double-float))
         (rhos (make-array rows :element-type 'double-float)))
    (dotimes (row rows)
      (let ((rho (loop for column from 1 below columns
                       for value = (aref distances row column)
                       when (plusp value) return value
                       finally (return 0.0d0)))
            (low 0.0d0)
            (high most-positive-double-float)
            (middle 1.0d0))
        (setf (aref rhos row) rho)
        (dotimes (iteration 64)
          (let ((sum
                  (loop for column from 1 below columns
                        for delta = (- (aref distances row column) rho)
                        sum (if (plusp delta)
                                (exp (- (/ delta middle)))
                                1.0d0))))
            (cond
              ((< (abs (- sum target)) 1.0d-5) (return))
              ((> sum target)
               (setf high middle
                     middle (/ (+ low high) 2.0d0)))
              (t
               (setf low middle
                     middle (if (= high most-positive-double-float)
                                (* middle 2.0d0)
                                (/ (+ low high) 2.0d0)))))))
        (setf (aref sigmas row)
              (max middle (* 1.0d-3 (cl-umap-row-mean distances row))))))
    (values sigmas rhos)))

(defun cl-umap-fuzzy-graph (indices distances sigmas rhos)
  (let* ((count (array-dimension indices 0))
         (neighbors (array-dimension indices 1))
         (directed (make-array (list count count)
                               :element-type 'double-float
                               :initial-element 0.0d0))
         (graph (make-array (list count count)
                            :element-type 'double-float
                            :initial-element 0.0d0)))
    (dotimes (row count)
      (dotimes (column neighbors)
        (let ((other (aref indices row column)))
          (unless (= row other)
            (let ((delta (- (aref distances row column) (aref rhos row))))
              (setf (aref directed row other)
                    (if (<= delta 0.0d0)
                        1.0d0
                        (exp (- (/ delta (aref sigmas row)))))))))))
    (dotimes (row count graph)
      (dotimes (column count)
        (let ((forward (aref directed row column))
              (backward (aref directed column row)))
          (setf (aref graph row column)
                (- (+ forward backward) (* forward backward))))))))

(defun cl-umap-curve-error (a b spread minimum-distance)
  (loop for index from 1 to 300
        for x = (* (/ index 100.0d0) spread)
        for target = (if (< x minimum-distance)
                         1.0d0
                         (exp (- (/ (- x minimum-distance) spread))))
        for fitted = (/ 1.0d0 (+ 1.0d0 (* a (expt x (* 2.0d0 b)))))
        for delta = (- target fitted)
        sum (* delta delta)))

(defun cl-umap-find-ab (spread minimum-distance)
  (let ((a-low 0.01d0) (a-high 8.0d0)
        (b-low 0.1d0) (b-high 3.0d0)
        (best-a 1.0d0) (best-b 1.0d0))
    (dotimes (round 7)
      (let ((best-error most-positive-double-float)
            (a-step (/ (- a-high a-low) 20.0d0))
            (b-step (/ (- b-high b-low) 20.0d0)))
        (dotimes (ai 21)
          (dotimes (bi 21)
            (let* ((a (+ a-low (* ai a-step)))
                   (b (+ b-low (* bi b-step)))
                   (error (cl-umap-curve-error a b spread minimum-distance)))
              (when (< error best-error)
                (setf best-error error best-a a best-b b)))))
        (setf a-low (max 1.0d-6 (- best-a a-step))
              a-high (+ best-a a-step)
              b-low (max 1.0d-6 (- best-b b-step))
              b-high (+ best-b b-step))))
    (values best-a best-b)))

(defun cl-umap-edge-vectors (graph epochs)
  (let* ((count (array-dimension graph 0))
         (maximum (loop for row below count
                        maximize (loop for column below count
                                       maximize (aref graph row column))))
         (threshold (/ maximum epochs))
         (heads (make-array 0 :element-type 'fixnum
                              :adjustable t :fill-pointer 0))
         (tails (make-array 0 :element-type 'fixnum
                              :adjustable t :fill-pointer 0))
         (weights (make-array 0 :element-type 'double-float
                                :adjustable t :fill-pointer 0)))
    (dotimes (row count)
      (dotimes (column count)
        (let ((weight (aref graph row column)))
          (when (>= weight threshold)
            (vector-push-extend column heads)
            (vector-push-extend row tails)
            (vector-push-extend weight weights)))))
    (values heads tails weights maximum)))

(defun cl-umap-clip (value)
  (max -4.0d0 (min 4.0d0 value)))

(defun cl-umap-optimize (graph epochs a b seed &key (negative-rate 5))
  (let* ((count (array-dimension graph 0))
         (rng (make-cl-umap-rng (if (zerop seed) 1 seed)))
         (coordinates (make-array (list count 2)
                                  :element-type 'double-float)))
    (dotimes (row count)
      (dotimes (column 2)
        (setf (aref coordinates row column)
              (- (* 20.0d0 (cl-umap-random-unit rng)) 10.0d0))))
    (multiple-value-bind (heads tails weights maximum)
        (cl-umap-edge-vectors graph epochs)
      (let* ((edge-count (length heads))
             (periods (make-array edge-count :element-type 'double-float))
             (next (make-array edge-count :element-type 'double-float)))
        (dotimes (edge edge-count)
          (let ((period (/ maximum (aref weights edge))))
            (setf (aref periods edge) period (aref next edge) period)))
        (dotimes (epoch epochs)
          (let ((alpha (- 1.0d0 (/ (coerce epoch 'double-float) epochs))))
            (dotimes (edge edge-count)
              (when (<= (aref next edge) epoch)
                (let* ((first (aref heads edge))
                       (second (aref tails edge))
                       (dx (- (aref coordinates first 0)
                              (aref coordinates second 0)))
                       (dy (- (aref coordinates first 1)
                              (aref coordinates second 1)))
                       (distance (+ (* dx dx) (* dy dy)))
                       (coefficient
                         (if (plusp distance)
                             (/ (* -2.0d0 a b (expt distance (1- b)))
                                (+ 1.0d0 (* a (expt distance b))))
                             0.0d0))
                       (gx (* alpha (cl-umap-clip (* coefficient dx))))
                       (gy (* alpha (cl-umap-clip (* coefficient dy)))))
                  (incf (aref coordinates first 0) gx)
                  (incf (aref coordinates first 1) gy)
                  (decf (aref coordinates second 0) gx)
                  (decf (aref coordinates second 1) gy)
                  (dotimes (sample negative-rate)
                    (let ((other (cl-umap-random-integer count rng)))
                      (unless (= first other)
                        (let* ((nx (- (aref coordinates first 0)
                                      (aref coordinates other 0)))
                               (ny (- (aref coordinates first 1)
                                      (aref coordinates other 1)))
                               (negative-distance
                                 (+ (* nx nx) (* ny ny)))
                               (negative-coefficient
                                 (if (plusp negative-distance)
                                     (/ (* 2.0d0 b)
                                        (* (+ 0.001d0 negative-distance)
                                           (+ 1.0d0
                                              (* a
                                                 (expt negative-distance b)))))
                                     0.0d0)))
                          (incf (aref coordinates first 0)
                                (* alpha
                                   (cl-umap-clip
                                    (* negative-coefficient nx))))
                          (incf (aref coordinates first 1)
                                (* alpha
                                   (cl-umap-clip
                                    (* negative-coefficient ny))))))))
                  (incf (aref next edge) (aref periods edge)))))))))
    coordinates))

(defun cl-umap-fit (input &key (neighbors 15) (minimum-distance 0.1d0)
                              (epochs 500) (seed 42) (standardize t))
  (cl-umap-check-input input)
  (unless (and (integerp neighbors)
               (> neighbors 1)
               (< neighbors (array-dimension input 0)))
    (error "Neighbors must be between 2 and N-1."))
  (unless (and (realp minimum-distance)
               (<= 0.0d0 minimum-distance 1.0d0))
    (error "Minimum distance must be between zero and one."))
  (unless (and (integerp epochs) (plusp epochs))
    (error "Epochs must be a positive integer."))
  (let ((working (if standardize (cl-umap-standardize input) input)))
    (multiple-value-bind (indices distances)
        (cl-umap-exact-neighbors working neighbors)
      (multiple-value-bind (sigmas rhos)
          (cl-umap-smooth-distances distances neighbors)
        (let ((graph (cl-umap-fuzzy-graph indices distances sigmas rhos)))
          (multiple-value-bind (a b)
              (cl-umap-find-ab 1.0d0
                               (coerce minimum-distance 'double-float))
            (make-cl-umap-result
             :input input
             :standardized-input working
             :neighbor-indices indices
             :neighbor-distances distances
             :sigmas sigmas
             :rhos rhos
             :fuzzy-graph graph
             :coordinates (cl-umap-optimize graph epochs a b seed)
             :neighbors neighbors
             :minimum-distance minimum-distance
             :epochs epochs
             :seed seed
             :a a
             :b b)))))))
