;;;; DBSCAN discovery and label classification for two-dimensional embeddings.

(defstruct embedding-cluster
  id
  size
  dominant-label
  dominant-count
  purity
  label-counts)

(defstruct embedding-clustering-result
  assignments
  epsilon
  minimum-points
  cluster-count
  noise-count
  classifications)

(defun embedding-distance (coordinates first second)
  (let ((dx (- (aref coordinates first 0) (aref coordinates second 0)))
        (dy (- (aref coordinates first 1) (aref coordinates second 1))))
    (sqrt (+ (* dx dx) (* dy dy)))))

(defun embedding-standardized-coordinates (coordinates)
  (let* ((count (array-dimension coordinates 0))
         (result (make-array (list count 2) :element-type 'double-float)))
    (dotimes (column 2)
      (let* ((mean (/ (loop for row below count
                            sum (aref coordinates row column))
                      count))
             (scale
               (sqrt (/ (loop for row below count
                              for delta = (- (aref coordinates row column) mean)
                              sum (* delta delta))
                        (max 1 (1- count))))))
        (dotimes (row count)
          (setf (aref result row column)
                (/ (- (aref coordinates row column) mean)
                   (if (zerop scale) 1.0d0 scale))))))
    result))

(defun embedding-region-query (coordinates point epsilon)
  (let ((neighbors '()))
    (dotimes (other (array-dimension coordinates 0) (nreverse neighbors))
      (when (<= (embedding-distance coordinates point other) epsilon)
        (push other neighbors)))))

(defun embedding-k-distance-values (coordinates minimum-points)
  (let* ((count (array-dimension coordinates 0))
         (values (make-array count :element-type 'double-float)))
    (dotimes (row count values)
      (let ((distances
              (sort (loop for other below count
                          collect (embedding-distance coordinates row other))
                    #'<)))
        (setf (aref values row) (nth (1- minimum-points) distances))))))

(defun embedding-knee-epsilon (coordinates minimum-points)
  (let* ((values (sort (coerce (embedding-k-distance-values
                                coordinates minimum-points)
                               'list)
                       #'<))
         (count (length values))
         (first (first values))
         (last (car (last values)))
         (best-index 0)
         (best-distance -1.0d0))
    (dotimes (index count)
      (let* ((x (/ (coerce index 'double-float) (max 1 (1- count))))
             (y (/ (- (nth index values) first)
                   (max 1.0d-12 (- last first))))
             (distance (- x y)))
        (when (> distance best-distance)
          (setf best-distance distance best-index index))))
    (max 1.0d-9 (nth best-index values))))

(defun embedding-expand-cluster (coordinates assignments seeds cluster-id
                                 epsilon minimum-points)
  (let ((queue (copy-list seeds)))
    (loop while queue do
      (let ((point (pop queue)))
        (when (= (aref assignments point) -1)
          (setf (aref assignments point) cluster-id))
        (when (= (aref assignments point) -2)
          (setf (aref assignments point) cluster-id)
          (let ((neighbors
                  (embedding-region-query coordinates point epsilon)))
            (when (>= (length neighbors) minimum-points)
              (dolist (neighbor neighbors)
                (when (member (aref assignments neighbor) '(-2 -1))
                  (pushnew neighbor queue))))))))))

(defun embedding-dbscan (coordinates epsilon minimum-points)
  (unless (and (arrayp coordinates) (= (array-rank coordinates) 2)
               (= (array-dimension coordinates 1) 2))
    (error "DBSCAN coordinates must be an N by 2 array."))
  (unless (and (realp epsilon) (plusp epsilon))
    (error "DBSCAN epsilon must be positive."))
  (unless (and (integerp minimum-points) (> minimum-points 1))
    (error "DBSCAN minimum-points must be at least two."))
  (let* ((count (array-dimension coordinates 0))
         (assignments (make-array count :element-type 'fixnum
                                        :initial-element -2))
         (cluster-id 0))
    (dotimes (point count)
      (when (= (aref assignments point) -2)
        (let ((neighbors (embedding-region-query coordinates point epsilon)))
          (if (< (length neighbors) minimum-points)
              (setf (aref assignments point) -1)
              (progn
                (embedding-expand-cluster coordinates assignments neighbors
                                          cluster-id epsilon minimum-points)
                (incf cluster-id))))))
    assignments))

(defun embedding-cluster-boundary-distance (coordinates assignments first second)
  "Return the smallest point distance between two non-noise clusters."
  (let ((best most-positive-double-float))
    (dotimes (left (length assignments) best)
      (when (= (aref assignments left) first)
        (dotimes (right (length assignments))
          (when (= (aref assignments right) second)
            (setf best (min best
                            (embedding-distance coordinates left right)))))))))

(defun embedding-cluster-adjacency-cost (coordinates assignments epsilon)
  "Mean normalized gap from each cluster to its nearest other cluster.

Coordinates are standardized before measuring. A zero cost means every
cluster has another cluster no farther away than EPSILON. Noise points are
ignored. Fewer than two discovered clusters have no adjacency relation and
therefore contribute zero cost."
  (unless (and (realp epsilon) (plusp epsilon))
    (error "Adjacency epsilon must be positive."))
  (let* ((standardized (embedding-standardized-coordinates coordinates))
         (maximum (loop for value across assignments maximize value))
         (cluster-count (1+ maximum)))
    (if (< cluster-count 2)
        0.0d0
        (/ (loop for cluster below cluster-count
                 for nearest =
                   (loop for other below cluster-count
                         unless (= cluster other)
                           minimize
                           (embedding-cluster-boundary-distance
                            standardized assignments cluster other))
                 sum (max 0.0d0 (- (/ nearest epsilon) 1.0d0)))
           cluster-count))))

(defun embedding-label-counts (assignments labels cluster-id)
  (let ((counts '()))
    (dotimes (index (length assignments) (nreverse counts))
      (when (= (aref assignments index) cluster-id)
        (let* ((label (aref labels index))
               (entry (assoc label counts :test #'equal)))
          (if entry
              (incf (cdr entry))
              (push (cons label 1) counts)))))))

(defun embedding-classify-clusters (assignments labels)
  (unless (= (length assignments) (length labels))
    (error "Cluster assignments and labels must have the same length."))
  (let ((maximum (loop for value across assignments maximize value))
        (results '()))
    (dotimes (cluster-id (1+ maximum) (nreverse results))
      (let* ((counts (embedding-label-counts assignments labels cluster-id))
             (size (reduce #'+ counts :key #'cdr :initial-value 0))
             (dominant
               (first (sort (copy-list counts)
                            (lambda (left right)
                              (or (> (cdr left) (cdr right))
                                  (and (= (cdr left) (cdr right))
                                       (string< (princ-to-string (car left))
                                                (princ-to-string
                                                 (car right))))))))))
        (push (make-embedding-cluster
               :id cluster-id
               :size size
               :dominant-label (car dominant)
               :dominant-count (cdr dominant)
               :purity (/ (coerce (cdr dominant) 'double-float) size)
               :label-counts counts)
              results)))))

(defun embedding-find-and-classify (coordinates labels
                                    &key (minimum-points 5) epsilon)
  (let* ((standardized (embedding-standardized-coordinates coordinates))
         (selected-epsilon
           (or epsilon (embedding-knee-epsilon standardized minimum-points)))
         (assignments
           (embedding-dbscan standardized selected-epsilon minimum-points))
         (cluster-count
           (1+ (loop for value across assignments maximize value)))
         (noise-count (count -1 assignments)))
    (make-embedding-clustering-result
     :assignments assignments
     :epsilon selected-epsilon
     :minimum-points minimum-points
     :cluster-count cluster-count
     :noise-count noise-count
     :classifications (embedding-classify-clusters assignments labels))))
