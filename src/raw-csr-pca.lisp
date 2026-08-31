;;;; Dependency-free preprocessing and PCA for a raw H5AD CSR count matrix.

(defun raw-vector-dot (left right)
  (loop for index below (length left)
        sum (* (aref left index) (aref right index)) into total
        finally (return (coerce total 'double-float))))

(defun raw-vector-norm (vector)
  (sqrt (raw-vector-dot vector vector)))

(defun raw-orthogonalize (vector basis)
  (dolist (axis basis vector)
    (let ((projection (raw-vector-dot vector axis)))
      (loop for index below (length vector) do
        (decf (aref vector index) (* projection (aref axis index)))))))

(defun raw-normalize-vector (vector)
  (let ((norm (raw-vector-norm vector)))
    (when (zerop norm) (error "PCA power iteration produced a zero vector."))
    (loop for index below (length vector) do
      (setf (aref vector index) (/ (aref vector index) norm)))
    vector))

(defun raw-matrix-vector (matrix vector)
  (let* ((size (length vector))
         (result (make-array size :element-type 'double-float)))
    (loop for row below size do
      (setf (aref result row)
            (loop for column below size
                  sum (* (aref matrix row column) (aref vector column))
                    into total
                  finally (return (coerce total 'double-float)))))
    result))

(defun raw-initial-axis (size component)
  (let ((axis (make-array size :element-type 'double-float)))
    (loop for index below size do
      (setf (aref axis index)
            (coerce (sin (* (1+ index) (+ component 1.61803398875d0)))
                    'double-float)))
    (raw-normalize-vector axis)))

(defun raw-principal-axes (gram components iterations)
  (let ((size (array-dimension gram 0)) axes eigenvalues)
    (loop for component below components do
      (let ((axis (raw-initial-axis size component)))
        (loop repeat iterations do
          (setf axis
                (raw-normalize-vector
                 (raw-orthogonalize (raw-matrix-vector gram axis) axes))))
        (let* ((product (raw-matrix-vector gram axis))
               (eigenvalue (max 0d0 (raw-vector-dot axis product))))
          (push axis axes)
          (push eigenvalue eigenvalues))))
    (values (nreverse axes) (nreverse eigenvalues))))

(defun raw-pca-scores (gram components iterations)
  (multiple-value-bind (axes eigenvalues)
      (raw-principal-axes gram components iterations)
    (let ((scores
           (loop repeat (array-dimension gram 0)
                 collect (make-array components
                                     :element-type 'double-float))))
      (loop for axis in axes
            for eigenvalue in eigenvalues
            for component from 0 do
        (let ((scale (sqrt eigenvalue)))
          (loop for row below (length scores) do
            (setf (aref (nth row scores) component)
                  (* scale (aref axis row))))))
      (mapcar (lambda (vector) (coerce vector 'list)) scores))))

(defun raw-median (numbers)
  (let* ((sorted (sort (copy-seq numbers) #'<))
         (size (length sorted))
         (middle (floor size 2)))
    (if (oddp size)
        (nth middle sorted)
        (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2d0))))

(defun raw-selected-cells (pointers minimum-genes)
  (loop for cell below (1- (length pointers))
        when (>= (- (aref pointers (1+ cell)) (aref pointers cell))
                 minimum-genes)
          collect cell))

(defun raw-gene-frequencies (selected indices pointers gene-count)
  (let ((frequencies (make-array gene-count :initial-element 0)))
    (dolist (cell selected frequencies)
      (loop for position from (aref pointers cell)
            below (aref pointers (1+ cell)) do
        (incf (aref frequencies (aref indices position)))))))

(defun raw-cell-totals (selected data indices pointers retained)
  (loop for cell in selected collect
    (loop for position from (aref pointers cell)
          below (aref pointers (1+ cell))
          for gene = (aref indices position)
          when (aref retained gene)
            sum (aref data position))))

(defun raw-gene-entries (selected data indices pointers retained target totals)
  (let ((entries (make-array (length retained) :initial-element nil)))
    (loop for cell in selected
          for row from 0
          for total in totals do
      (let ((scale (/ target total)))
        (loop for position from (aref pointers cell)
              below (aref pointers (1+ cell))
              for gene = (aref indices position)
              when (aref retained gene) do
                (let ((value (log (1+ (* scale (aref data position))) 10d0)))
                  (push (cons row (coerce value 'double-float))
                        (aref entries gene))))))
    entries))

(defun raw-centered-gram (entries cell-count)
  (let ((gram (make-array (list cell-count cell-count)
                          :element-type 'double-float
                          :initial-element 0d0))
        (row-mean-products
         (make-array cell-count :element-type 'double-float
                                :initial-element 0d0))
        (mean-square-sum 0d0))
    (loop for gene-entries across entries
          unless (null gene-entries) do
      (let ((mean (/ (loop for entry in gene-entries sum (cdr entry))
                     cell-count)))
        (incf mean-square-sum (* mean mean))
        (dolist (entry gene-entries)
          (incf (aref row-mean-products (car entry)) (* (cdr entry) mean)))
        (dolist (left gene-entries)
          (dolist (right gene-entries)
            (incf (aref gram (car left) (car right))
                  (* (cdr left) (cdr right)))))))
    (loop for row below cell-count do
      (loop for column below cell-count do
        (incf (aref gram row column)
              (+ (- (aref row-mean-products row))
                 (- (aref row-mean-products column))
                 mean-square-sum))))
    gram))

(defun raw-csr-pca (path specification)
  (let* ((group (or (getf specification :group) "/X"))
         (data (coerce
                (parse-h5-values
                 (h5dump-output path (concatenate 'string group "/data")))
                'vector))
         (indices (coerce
                   (parse-h5-values
                    (h5dump-output path (concatenate 'string group "/indices")))
                   'vector))
         (pointers (coerce
                    (parse-h5-values
                     (h5dump-output path (concatenate 'string group "/indptr")))
                    'vector))
         (gene-count (or (getf specification :gene-count)
                         (1+ (reduce #'max indices))))
         (minimum-genes (or (getf specification :minimum-genes) 200))
         (minimum-cells (or (getf specification :minimum-cells) 3))
         (components (or (getf specification :components) 20))
         (iterations (or (getf specification :iterations) 10))
         (selected (raw-selected-cells pointers minimum-genes))
         (frequencies
          (raw-gene-frequencies selected indices pointers gene-count))
         (retained (make-array gene-count :initial-element nil)))
    (loop for gene below gene-count do
      (setf (aref retained gene) (>= (aref frequencies gene) minimum-cells)))
    (let* ((totals (raw-cell-totals selected data indices pointers retained))
           (target (raw-median totals))
           (entries
            (raw-gene-entries selected data indices pointers retained target totals))
           (gram (raw-centered-gram entries (length selected)))
           (scores (raw-pca-scores gram components iterations)))
      (format t
              "Raw CSR: ~D/~D cells, ~D/~D genes; normalize target ~,2F; ~D PCs.~%"
              (length selected) (1- (length pointers))
              (count t retained) gene-count target components)
      (values scores selected))))
