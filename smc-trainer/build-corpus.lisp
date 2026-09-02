;;;; Build numeric supervision from an AWRS-SMC winning UMAP.

(defparameter *parametric-corpus-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *parametric-corpus-root*
  (merge-pathnames "../" *parametric-corpus-directory*))
(defparameter *smc-search-run-main* nil)
(load (merge-pathnames "smc/search-umap.lisp" *parametric-corpus-root*))

(defun parametric-repository-relative-name (path)
  "Return PATH relative to the repository root without embedding a machine path."
  (let* ((root (namestring (truename *parametric-corpus-root*)))
         (full (namestring (truename path)))
         (root-length (length root)))
    (if (and (<= root-length (length full))
             (string= root full :end2 root-length))
        (subseq full root-length)
        (file-namestring full))))

(defun parametric-column-statistics (array)
  (let* ((rows (array-dimension array 0))
         (columns (array-dimension array 1))
         (means (make-array columns :element-type 'double-float))
         (scales (make-array columns :element-type 'double-float)))
    (dotimes (column columns)
      (let* ((mean (/ (loop for row below rows
                            sum (aref array row column))
                      rows))
             (scale
               (sqrt (/ (loop for row below rows
                              for delta = (- (aref array row column) mean)
                              sum (* delta delta))
                        (max 1 (1- rows))))))
        (setf (aref means column) mean
              (aref scales column) (if (zerop scale) 1.0d0 scale))))
    (values means scales)))

(defun parametric-standardize (array means scales)
  (let* ((rows (array-dimension array 0))
         (columns (array-dimension array 1))
         (result (make-array (list rows columns)
                             :element-type 'double-float)))
    (dotimes (row rows result)
      (dotimes (column columns)
        (setf (aref result row column)
              (/ (- (aref array row column) (aref means column))
                 (aref scales column)))))))

(defun parametric-array-row (array row)
  (loop for column below (array-dimension array 1)
        collect (aref array row column)))

(defun parametric-best-choices (features declarations)
  (mapcar
   (lambda (feature)
     (let ((entry (find (smc-feature-name feature) declarations
                        :key (lambda (item) (getf item :name)) :test #'eq)))
       (if entry (getf entry :transformation) :exclude)))
   features))

(defun parametric-record-group (record)
  (or (getf record :study) (getf record :curve-id) (getf record :id)
      (error "Corpus observation has no study, curve, or record identifier.")))

(defun parametric-validation-groups (records)
  (let* ((groups (sort (remove-duplicates
                        (mapcar #'parametric-record-group records)
                        :test #'equal)
                       #'string< :key #'princ-to-string))
         (count (length groups))
         (validation-count (if (> count 1) (max 1 (floor count 5)) 0)))
    (last groups validation-count)))

(defun build-parametric-umap-corpus (result-name output-name)
  (let* ((result-path (truename result-name))
         (result (smc-read-form result-path))
         (best (or (getf result :best)
                   (error "AWRS-SMC result has no :BEST entry.")))
         (coordinates (or (getf best :coordinates)
                          (error "AWRS-SMC result has no preserved winning coordinates.")))
         (search-path (truename (getf result :search-file)))
         (search (smc-read-form search-path))
         (manifest-path (truename (getf result :manifest)))
         (manifest-directory (make-pathname :name nil :type nil
                                             :defaults manifest-path))
         (problem (read-form-file manifest-path))
         (data-spec (getf problem :data))
         (records (read-dataset
                   (merge-pathnames (getf data-spec :file) manifest-directory)
                   data-spec))
         (settings (getf result :settings))
         (limit (getf settings :maximum-observations))
         (used-count (if limit (min limit (length records)) (length records)))
         (used-records (subseq records 0 used-count))
         (input (score-umap-record-array records))
         (features
           (mapcar (lambda (form)
                     (smc-feature-from-form form (array-dimension input 1)))
                   (getf search :features)))
         (declarations (getf best :features))
         (choices (parametric-best-choices features declarations))
         (selected (smc-selected-feature-array input features choices limit))
         (epsilon
           (let ((value (getf settings :epsilon :automatic)))
             (if (eq value :automatic)
                 (embedding-knee-epsilon
                  (embedding-standardized-coordinates coordinates)
                  (or (getf settings :minimum-points) 5))
                 value)))
         (assignments
           (embedding-dbscan (embedding-standardized-coordinates coordinates)
                             epsilon
                             (or (getf settings :minimum-points) 5)))
         (validation-groups (parametric-validation-groups used-records))
         (output-path (pathname output-name)))
    (unless (and (= (array-rank coordinates) 2)
                 (= (array-dimension coordinates 0) used-count)
                 (= (array-dimension coordinates 1) 2))
      (error "Winning coordinates must be a ~D by 2 array." used-count))
    (multiple-value-bind (means scales) (parametric-column-statistics selected)
      (let* ((standardized (parametric-standardize selected means scales))
             (corpus
               (list
                :format :parametric-umap-corpus :version 1
                :annotation-source :awrs-smc-winning-common-lisp-umap
                :source-result (parametric-repository-relative-name result-path)
                :coordinate-source (getf best :coordinate-source)
                :feature-schema declarations
                :preprocessing
                (list :standardize t
                      :means (coerce means 'list)
                      :scales (coerce scales 'list)
                      :fit-population :winning-atlas)
                :split-policy
                (list :kind :study-grouped
                      :validation-groups validation-groups)
                :records
                (loop for record in used-records for row from 0
                      for group = (parametric-record-group record)
                      collect
                      (list :id (getf record :id)
                            :group group
                            :split (if (member group validation-groups
                                               :test #'equal)
                                       :validation :train)
                            :input (parametric-array-row standardized row)
                            :target (parametric-array-row coordinates row)
                            :cluster (aref assignments row)
                            :label (getf record
                                         (or (getf search :label-field)
                                             (getf (getf problem :scoring)
                                                   :label-field))))))))
        (ensure-directories-exist output-path)
        (with-open-file (stream output-path :direction :output
                                           :if-exists :supersede
                                           :if-does-not-exist :create)
          (let ((*print-pretty* t) (*print-length* nil) (*print-level* nil))
            (prin1 corpus stream) (terpri stream)))
        (format t "Wrote ~D annotated examples (~D train, ~D validation) to ~A.~%"
                used-count
                (count :train (getf corpus :records)
                       :key (lambda (record) (getf record :split)))
                (count :validation (getf corpus :records)
                       :key (lambda (record) (getf record :split)))
                output-path)
        output-path))))

(defun parametric-corpus-main ()
  (let ((arguments (cdr sb-ext:*posix-argv*)))
    (unless (= (length arguments) 2)
      (error "Usage: sbcl --script smc-trainer/build-corpus.lisp AWRS-RESULT.sexp OUTPUT.sexp"))
    (build-parametric-umap-corpus (first arguments) (second arguments))))

(parametric-corpus-main)
