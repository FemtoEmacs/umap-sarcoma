;;;; Experiment 7: endpoint-appropriate transforms for non-survival evidence.

(defparameter *experiment-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *project-root* (merge-pathnames "../" *experiment-root*))
(load (merge-pathnames "src/evidence-windows.lisp" *project-root*))
(setf *evidence-use-typed-transforms* t)

(defun experiment-read (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (read stream))))

(let* ((source (experiment-read
                (merge-pathnames "data/pilot-landmarks.sexp" *project-root*)))
       (records (evidence-all-multiscale-records (getf source :curves)))
       (output (merge-pathnames "typed-transforms-windows.sexp"
                                *experiment-root*)))
  (with-open-file (stream output :direction :output :if-exists :supersede
                                 :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-circle* nil))
      (prin1 (list :schema 'evidence-windows/1 :records records) stream)
      (terpri stream)))
  (unless (and (= 600 (length records))
               (every (lambda (record) (= 23 (length (getf record :vector))))
                      records))
    (error "Expected 600 records with 23 dimensions."))
  (format t "Wrote ~A with typed transforms.~%" output))
