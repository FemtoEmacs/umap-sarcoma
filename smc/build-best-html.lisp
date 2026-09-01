;;;; Materialize the best SMC recipe as data, a manifest, and an HTML page.

(defparameter *smc-best-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *smc-search-run-main* nil)
(load (merge-pathnames "search-umap.lisp" *smc-best-directory*))

(defun smc-write-form (form path)
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-circle* nil)
          (*print-length* nil) (*print-level* nil))
      (prin1 form stream)
      (terpri stream))))

(defun smc-replace-plist-value (plist key value)
  (let ((copy (copy-tree plist)))
    (setf (getf copy key) value)
    copy))

(defun smc-materialized-records (records input features choices limit)
  (let* ((count (if limit (min limit (length records)) (length records)))
         (array (smc-selected-feature-array input features choices limit)))
    (loop for record in records for row below count collect
      (smc-replace-plist-value
       record :vector
       (loop for column below (array-dimension array 1)
             collect (aref array row column))))))

(defun smc-best-html (result-name &optional output-name)
  (let* ((result-path (truename result-name))
         (result (smc-read-form result-path))
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
         (input (score-umap-record-array records))
         (features
           (mapcar (lambda (form)
                     (smc-feature-from-form form (array-dimension input 1)))
                   (getf search :features)))
         (best (or (getf result :best)
                   (error "The search result has no :BEST configuration.")))
         (best-declarations (getf best :features))
         (choices
           (mapcar
            (lambda (feature)
              (let ((declaration
                      (find (smc-feature-name feature) best-declarations
                            :key (lambda (item) (getf item :name)) :test #'eq)))
                (if declaration (getf declaration :transformation) :exclude)))
            features))
         (settings (getf result :settings))
         (materialized
           (smc-materialized-records
            records input features choices (getf settings :maximum-observations)))
         (output (or output-name
                     (namestring
                      (merge-pathnames
                       (format nil "~A-best.html" (pathname-name result-path))
                       (make-pathname :name nil :type nil :defaults result-path)))))
         (output-path (pathname output))
         (output-directory (make-pathname :name nil :type nil
                                           :defaults output-path))
         (stem (pathname-name output-path))
         (data-path (merge-pathnames (format nil "~A-data.sexp" stem)
                                     output-directory))
         (page-manifest-path
           (merge-pathnames (format nil "~A-problem.sexp" stem)
                            output-directory))
         (page-data-spec
           (smc-replace-plist-value
            data-spec :file (file-namestring data-path)))
         (page-problem (copy-tree problem)))
    (setf (getf page-problem :title)
          (format nil "~A — best SMC feature set" (getf problem :title)))
    (setf (getf page-problem :preparation) nil)
    (setf (getf page-problem :data) page-data-spec)
    (setf (getf page-problem :umap)
          (list :neighbors (or (getf settings :neighbors) 15)
                :minimum-distance (or (getf settings :minimum-distance) 0.1d0)
                :epochs (or (getf settings :epochs) 50)
                :seed (or (getf settings :umap-seed) 42)
                :density-surface t :density-bandwidth 45
                :density-thresholds 10 :density-opacity 0.18d0
                :density-color "data" :density-color-bands 7
                :point-radius 6))
    (smc-write-form (list :format :umap-data :version 1
                          :records materialized)
                    data-path)
    (smc-write-form page-problem page-manifest-path)
    (build-umap-html page-manifest-path output-path)
    (format t "Best search score: ~,6F~%Features: ~S~%"
            (getf best :score) best-declarations)
    (format t "Open ~A in a web browser.~%" output-path)
    output-path))

(defun smc-best-html-main ()
  (let ((arguments (cdr *posix-argv*)))
    (unless (<= 1 (length arguments) 2)
      (error "Usage: sbcl --script smc/build-best-html.lisp RESULT.sexp [OUTPUT.html]"))
    (smc-best-html (first arguments) (second arguments))))

(smc-best-html-main)
