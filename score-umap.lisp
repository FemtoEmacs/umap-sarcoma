;;;; Manifest-driven Common Lisp UMAP, clustering, classification, and score.

(defparameter *score-umap-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defvar *score-umap-run-main* t)

;; Reuse exactly the manifest and dataset readers used by build-umap.lisp.
(defparameter *build-umap-run-main* nil)
(unless (fboundp 'read-dataset)
  (load (merge-pathnames "build-umap.lisp" *score-umap-root*)))
(unless (fboundp 'cl-umap-fit)
  (load (merge-pathnames "src/common-lisp-umap.lisp" *score-umap-root*)))
(unless (fboundp 'embedding-find-and-classify)
  (load (merge-pathnames "src/embedding-clusters.lisp" *score-umap-root*)))
(unless (fboundp 'umap-v-measure-from-vectors)
  (load (merge-pathnames "src/v-measure.lisp" *score-umap-root*)))

(defun score-umap-record-array (records)
  (unless records
    (error "The manifest dataset contains no observations."))
  (let* ((dimensions (length (getf (first records) :vector)))
         (array (make-array (list (length records) dimensions)
                            :element-type 'double-float)))
    (unless (plusp dimensions)
      (error "The manifest embedding produced an empty feature vector."))
    (loop for record in records
          for row from 0
          for vector = (getf record :vector) do
      (unless (and (listp vector) (= (length vector) dimensions))
        (error "Observation ~D has an invalid or inconsistent vector." row))
      (dotimes (column dimensions)
        (let ((value (nth column vector)))
          (unless (realp value)
            (error "Observation ~D feature ~D is not numeric: ~S."
                   row column value))
          (setf (aref array row column) (coerce value 'double-float)))))
    array))

(defun score-umap-label-vector (records field)
  (unless field
    (error "The manifest requires :SCORING (:LABEL-FIELD ...)."))
  (let ((labels (make-array (length records))))
    (loop for record in records
          for index from 0 do
      (unless (record-has-field-p record field)
        (error "Observation ~D lacks scoring label field ~A." index field))
      (setf (aref labels index) (getf record field)))
    labels))

(defun score-umap-result-form (manifest-path data-path umap clustering score
                               label-field)
  (list
   :format 'common-lisp-umap-result
   :version 1
   :manifest (namestring manifest-path)
   :data-file (namestring data-path)
   :label-field label-field
   :parameters
   (list :neighbors (cl-umap-result-neighbors umap)
         :minimum-distance (cl-umap-result-minimum-distance umap)
         :epochs (cl-umap-result-epochs umap)
         :seed (cl-umap-result-seed umap)
         :a (cl-umap-result-a umap)
         :b (cl-umap-result-b umap))
   :observation-count (array-dimension (cl-umap-result-input umap) 0)
   :feature-count (array-dimension (cl-umap-result-input umap) 1)
   :coordinates (cl-umap-result-coordinates umap)
   :clustering
   (list :algorithm :dbscan
         :epsilon (embedding-clustering-result-epsilon clustering)
         :minimum-points
         (embedding-clustering-result-minimum-points clustering)
         :cluster-count
         (embedding-clustering-result-cluster-count clustering)
         :noise-count (embedding-clustering-result-noise-count clustering)
         :assignments (embedding-clustering-result-assignments clustering)
         :classifications
         (mapcar
          (lambda (cluster)
            (list :id (embedding-cluster-id cluster)
                  :size (embedding-cluster-size cluster)
                  :dominant-label (embedding-cluster-dominant-label cluster)
                  :dominant-count (embedding-cluster-dominant-count cluster)
                  :purity (embedding-cluster-purity cluster)
                  :label-counts (embedding-cluster-label-counts cluster)))
          (embedding-clustering-result-classifications clustering)))
   :v-measure
   (list :homogeneity (umap-v-measure-result-homogeneity score)
         :completeness (umap-v-measure-result-completeness score)
         :v-measure (umap-v-measure-result-v-measure score)
         :contingency (umap-v-measure-result-contingency score))))

(defun score-umap-default-output (manifest-path scoring directory)
  (let ((declared (getf scoring :output)))
    (if declared
        (merge-pathnames declared directory)
        (merge-pathnames
         (format nil "output/~A-score.sexp"
                 (pathname-name manifest-path))
         directory))))

(defun score-umap-manifest (manifest-name &optional output-name)
  (let* ((manifest-path (truename (resolve-manifest manifest-name)))
         (directory (make-pathname :name nil :type nil
                                   :defaults manifest-path))
         (problem (read-form-file manifest-path))
         (data-spec (getf problem :data))
         (data-path (merge-pathnames (getf data-spec :file) directory))
         (records (read-dataset data-path data-spec))
         (input (score-umap-record-array records))
         (scoring
           (or (getf problem :scoring)
               (error "The manifest has no :SCORING section.")))
         (label-field (getf scoring :label-field))
         (labels (score-umap-label-vector records label-field))
         (umap-spec (getf problem :umap))
         (preprocessing (getf problem :preprocessing))
         (clustering-spec (getf scoring :clustering))
         (algorithm (or (getf clustering-spec :algorithm) :dbscan))
         (minimum-points (or (getf clustering-spec :minimum-points) 5))
         (epsilon-request (getf clustering-spec :epsilon :automatic))
         (epsilon (unless (eq epsilon-request :automatic) epsilon-request))
         (neighbors (or (getf umap-spec :neighbors) 15))
         (minimum-distance (or (getf umap-spec :minimum-distance) 0.1d0))
         (epochs (or (getf umap-spec :epochs) 500))
         (seed (or (getf umap-spec :seed) 42))
         (standardize (not (null (getf preprocessing :standardize t))))
         (beta (or (getf scoring :beta) 1.0d0))
         (output-path
           (if output-name
               (pathname output-name)
               (score-umap-default-output manifest-path scoring directory))))
    (unless (eq algorithm :dbscan)
      (error "Unsupported clustering algorithm ~S; expected :DBSCAN."
             algorithm))
    (let* ((umap (cl-umap-fit input :neighbors neighbors
                                     :minimum-distance minimum-distance
                                     :epochs epochs :seed seed
                                     :standardize standardize))
           (clustering
             (embedding-find-and-classify
              (cl-umap-result-coordinates umap) labels
              :minimum-points minimum-points :epsilon epsilon))
           (score
             (umap-v-measure-from-vectors
              labels (embedding-clustering-result-assignments clustering)
              :beta beta)))
      (ensure-directories-exist output-path)
      (with-open-file (stream output-path :direction :output
                                         :if-exists :supersede
                                         :if-does-not-exist :create)
        (let ((*print-pretty* t) (*print-circle* nil)
              (*print-length* nil) (*print-level* nil))
          (prin1 (score-umap-result-form
                  manifest-path data-path umap clustering score label-field)
                 stream)
          (terpri stream)))
      (format t "Manifest: ~A~%Data: ~A (~D observations, ~D features).~%"
              manifest-path data-path
              (array-dimension input 0) (array-dimension input 1))
      (format t "DBSCAN: epsilon=~,6F clusters=~D noise=~D.~%"
              (embedding-clustering-result-epsilon clustering)
              (embedding-clustering-result-cluster-count clustering)
              (embedding-clustering-result-noise-count clustering))
      (dolist (cluster
                (embedding-clustering-result-classifications clustering))
        (format t "  cluster ~D: n=~D dominant=~A purity=~,4F counts=~S~%"
                (embedding-cluster-id cluster)
                (embedding-cluster-size cluster)
                (embedding-cluster-dominant-label cluster)
                (embedding-cluster-purity cluster)
                (embedding-cluster-label-counts cluster)))
      (format t "V-measure: homogeneity=~,6F completeness=~,6F V=~,6F~%"
              (umap-v-measure-result-homogeneity score)
              (umap-v-measure-result-completeness score)
              (umap-v-measure-result-v-measure score))
      (format t "Wrote ~A~%" output-path)
      (values umap clustering score output-path))))

(defun score-umap-main ()
  (let ((arguments (cdr *posix-argv*)))
    (unless (<= 1 (length arguments) 2)
      (error "Usage: sbcl --script score-umap.lisp MANIFEST [OUTPUT.sexp]"))
    (score-umap-manifest (first arguments) (second arguments))))

(when *score-umap-run-main*
  (score-umap-main))
