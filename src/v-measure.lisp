;;;; Dependency-free V-measure scoring for labeled two-dimensional embeddings.

(defstruct (umap-score-input
             (:constructor %make-umap-score-input
                 (coordinates labels clusters)))
  coordinates
  labels
  clusters)

(defstruct umap-v-measure-result
  homogeneity
  completeness
  v-measure
  beta
  observation-count
  label-values
  cluster-values
  contingency)

(defun umap-ensure-vector (value name)
  (unless (vectorp value)
    (error "~A must be a vector." name))
  value)

(defun umap-validate-coordinates (coordinates observation-count)
  (unless (and (arrayp coordinates)
               (= (array-rank coordinates) 2)
               (= (array-dimension coordinates 0) observation-count)
               (= (array-dimension coordinates 1) 2))
    (error "Coordinates must be an N by 2 array matching the label count."))
  (dotimes (row observation-count)
    (dotimes (column 2)
      (unless (realp (aref coordinates row column))
        (error "Coordinate at row ~D, column ~D is not real."
               row column))))
  coordinates)

(defun make-umap-score-input (coordinates labels clusters)
  (umap-ensure-vector labels "Labels")
  (umap-ensure-vector clusters "Clusters")
  (let ((count (length labels)))
    (when (zerop count)
      (error "At least one observation is required."))
    (unless (= count (length clusters))
      (error "Labels and clusters must have the same length."))
    (umap-validate-coordinates coordinates count)
    (%make-umap-score-input coordinates labels clusters)))

(defun umap-unique-values (values)
  (let ((unique '()))
    (dotimes (index (length values))
      (let ((value (aref values index)))
        (unless (member value unique :test #'equal)
          (setf unique (append unique (list value))))))
    (coerce unique 'vector)))

(defun umap-value-index (value values)
  (or (position value values :test #'equal)
      (error "Internal error: value ~S is absent from its index." value)))

(defun umap-contingency-table (labels clusters label-values cluster-values)
  (let ((table (make-array (list (length label-values)
                                 (length cluster-values))
                           :element-type 'integer
                           :initial-element 0)))
    (dotimes (index (length labels))
      (let ((row (umap-value-index (aref labels index) label-values))
            (column (umap-value-index (aref clusters index)
                                      cluster-values)))
        (incf (aref table row column))))
    table))

(defun umap-row-counts (table)
  (let* ((rows (array-dimension table 0))
         (columns (array-dimension table 1))
         (counts (make-array rows :element-type 'integer)))
    (dotimes (row rows counts)
      (setf (aref counts row)
            (loop for column below columns
                  sum (aref table row column))))))

(defun umap-column-counts (table)
  (let* ((rows (array-dimension table 0))
         (columns (array-dimension table 1))
         (counts (make-array columns :element-type 'integer)))
    (dotimes (column columns counts)
      (setf (aref counts column)
            (loop for row below rows
                  sum (aref table row column))))))

(defun umap-count-entropy (counts total)
  (let ((entropy 0.0d0)
        (denominator (coerce total 'double-float)))
    (dotimes (index (length counts) entropy)
      (let ((count (aref counts index)))
        (when (plusp count)
          (let ((probability (/ (coerce count 'double-float)
                                denominator)))
            (decf entropy (* probability (log probability)))))))))

(defun umap-joint-entropy (table total)
  (let ((entropy 0.0d0)
        (denominator (coerce total 'double-float)))
    (dotimes (row (array-dimension table 0) entropy)
      (dotimes (column (array-dimension table 1))
        (let ((count (aref table row column)))
          (when (plusp count)
            (let ((probability (/ (coerce count 'double-float)
                                  denominator)))
              (decf entropy (* probability (log probability))))))))))

(defun umap-unit-interval (value)
  (max 0.0d0 (min 1.0d0 value)))

(defun umap-v-measure-from-vectors (labels clusters &key (beta 1.0d0))
  (umap-ensure-vector labels "Labels")
  (umap-ensure-vector clusters "Clusters")
  (unless (and (realp beta) (plusp beta))
    (error "Beta must be a positive real number."))
  (let ((count (length labels)))
    (when (zerop count)
      (error "At least one observation is required."))
    (unless (= count (length clusters))
      (error "Labels and clusters must have the same length."))
    (let* ((label-values (umap-unique-values labels))
           (cluster-values (umap-unique-values clusters))
           (table (umap-contingency-table labels clusters
                                          label-values cluster-values))
           (label-entropy (umap-count-entropy (umap-row-counts table) count))
           (cluster-entropy
             (umap-count-entropy (umap-column-counts table) count))
           (joint-entropy (umap-joint-entropy table count))
           (homogeneity
             (umap-unit-interval
              (if (zerop label-entropy)
                  1.0d0
                  (- 1.0d0 (/ (- joint-entropy cluster-entropy)
                              label-entropy)))))
           (completeness
             (umap-unit-interval
              (if (zerop cluster-entropy)
                  1.0d0
                  (- 1.0d0 (/ (- joint-entropy label-entropy)
                              cluster-entropy)))))
           (beta-value (coerce beta 'double-float))
           (v-measure
             (if (zerop (+ homogeneity completeness))
                 0.0d0
                 (/ (* (+ 1.0d0 beta-value)
                       homogeneity completeness)
                    (+ (* beta-value homogeneity) completeness)))))
      (make-umap-v-measure-result
       :homogeneity homogeneity
       :completeness completeness
       :v-measure (umap-unit-interval v-measure)
       :beta beta-value
       :observation-count count
       :label-values label-values
       :cluster-values cluster-values
       :contingency table))))

(defun score-umap-clusters (input &key (beta 1.0d0))
  (unless (typep input 'umap-score-input)
    (error "Input must be an UMAP-SCORE-INPUT."))
  (umap-v-measure-from-vectors
   (umap-score-input-labels input)
   (umap-score-input-clusters input)
   :beta beta))
