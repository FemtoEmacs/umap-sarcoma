;;;; tr.lisp -- command-line Prolog -> qprolog translator, used by the ./tr.x script.
;;;;   ./tr.x IN.pl [OUT.lisp]
(let ((*standard-output* (make-broadcast-stream)) (*error-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (load (merge-pathnames "bench/pl2lispy.lisp" (or *load-truename* *load-pathname*)))))

(defun tr-main (args)
  (let* ((in (first args))
         (out (or (second args)
                  (concatenate 'string (subseq in 0 (or (search ".pl" in :from-end t) (length in))) ".lisp"))))
    (handler-case
        (progn
          (unless (probe-file in) (format t "tr.x: no such file: ~A~%" in) (sb-ext:exit :code 1))
          (let ((pl2lispy::*qp-mode* t))
            (handler-bind ((warning #'muffle-warning))
              (pl2lispy:translate-file in out)))
          (format t "~A -> ~A~%" in out))
      (error (c) (format t "tr.x: cannot translate ~A: ~A~%" in c) (sb-ext:exit :code 1)))))

(let ((args (cdr sb-ext:*posix-argv*)))
  (if (null args)
      (progn (format t "usage: ./tr.x IN.pl [OUT.lisp]      (OUT defaults to IN with .lisp)~%") (sb-ext:exit :code 2))
      (tr-main args)))
