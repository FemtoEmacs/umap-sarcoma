;;;; Build pilot evidence-window records. SBCL; no Quicklisp.

(defparameter *evidence-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(load (merge-pathnames "src/evidence-windows.lisp" *evidence-root*))

(defun evidence-read (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (read stream))))

(let* ((source (evidence-read
                (merge-pathnames "data/pilot-landmarks.sexp" *evidence-root*)))
       (records (evidence-all-multiscale-records (getf source :curves)))
       (output (merge-pathnames "data/pilot-windows.sexp" *evidence-root*)))
  (with-open-file (stream output :direction :output :if-exists :supersede
                                 :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-circle* nil))
      (prin1 (list :schema 'evidence-windows/1 :records records) stream)
      (terpri stream)))
  (format t "Wrote ~A with ~D evidence windows.~%" output (length records)))
