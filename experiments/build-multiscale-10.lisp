;;;; Experiment 2: ten temporal anchors at three window scales.

(defparameter *experiment-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *project-root* (merge-pathnames "../" *experiment-root*))
(load (merge-pathnames "src/evidence-windows.lisp" *project-root*))

(setf *evidence-temporal-profile-count* 10)

(defun experiment-read (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (read stream))))

(let* ((source (experiment-read
                (merge-pathnames "data/pilot-landmarks.sexp" *project-root*)))
       (curves (getf source :curves))
       (records
        (loop for width in '(0.125d0 0.25d0 0.50d0)
              do (setf *evidence-window-width* width)
              append (evidence-all-window-records curves)))
       (output (merge-pathnames "multiscale-10-windows.sexp" *experiment-root*)))
  (with-open-file (stream output :direction :output :if-exists :supersede
                                 :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-circle* nil))
      (prin1 (list :schema 'evidence-windows/1 :records records) stream)
      (terpri stream)))
  (unless (= 600 (length records))
    (error "Expected 600 multiscale records; found ~D." (length records)))
  (format t "Wrote ~A with ~D records.~%" output (length records)))
