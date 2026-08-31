;;;; Reversible experiment: reduce temporal oversampling to twenty anchors.

(defparameter *experiment-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *project-root* (merge-pathnames "../" *experiment-root*))

(load (merge-pathnames "src/evidence-windows.lisp" *project-root*))
(setf *evidence-temporal-profile-count* 20)

(defun experiment-read (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (read stream))))

(let* ((source (experiment-read
                (merge-pathnames "data/pilot-landmarks.sexp" *project-root*)))
       (records (evidence-all-window-records (getf source :curves)))
       (output (merge-pathnames "temporal-20-windows.sexp" *experiment-root*)))
  (with-open-file (stream output :direction :output :if-exists :supersede
                                 :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-circle* nil))
      (prin1 (list :schema 'evidence-windows/1 :records records) stream)
      (terpri stream)))
  (unless (= 400 (length records))
    (error "Expected 400 temporal-anchor records; found ~D." (length records)))
  (format t "Wrote ~A with ~D records.~%" output (length records)))
