;;;; Experiment 3: complementary log-log survival coordinates.

(defparameter *experiment-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *project-root* (merge-pathnames "../" *experiment-root*))
(load (merge-pathnames "src/evidence-windows.lisp" *project-root*))

(setf *evidence-temporal-profile-count* 10
      *evidence-survival-transform* :cloglog)

(defun experiment-read (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (read stream))))

(let* ((source (experiment-read
                (merge-pathnames "data/pilot-landmarks.sexp" *project-root*)))
       (records (evidence-all-multiscale-records (getf source :curves)))
       (output (merge-pathnames "cloglog-multiscale-windows.sexp"
                                *experiment-root*)))
  (with-open-file (stream output :direction :output :if-exists :supersede
                                 :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-circle* nil))
      (prin1 (list :schema 'evidence-windows/1 :records records) stream)
      (terpri stream)))
  (unless (= 600 (length records))
    (error "Expected 600 transformed records; found ~D." (length records)))
  (unless (every (lambda (record)
                   (every (lambda (value) (and (numberp value) (= value value)))
                          (getf record :vector)))
                 records)
    (error "Complementary log-log experiment produced a non-finite feature."))
  (format t "Wrote ~A with ~D records.~%" output (length records)))
