;;;; consult.lisp -- load ordinary Prolog text (.pl) by translating it on the fly with
;;;; bench/pl2lispy.lisp (loaded the first time it is needed).
;;;;   (qp::consult-pl "prog.pl")     or, from Prolog,   (consult "prog.pl")
;;;; (qp::load-qp "prog.pl") also does this for files ending in .pl.
(in-package :qp)

(defvar *pl2lispy-path*
  (merge-pathnames "../bench/pl2lispy.lisp" (or *load-truename* *load-pathname*)))

(defun ensure-pl2lispy ()
  (unless (find-package :pl2lispy)
    (let ((*standard-output* (make-broadcast-stream)) (*error-output* (make-broadcast-stream)))
      (handler-bind ((warning #'muffle-warning))
        (load *pl2lispy-path*)))))

(defun pl2lispy-fn (name) (symbol-function (find-symbol name :pl2lispy)))

(defun consult-pl (file)
  "Translate the Prolog text in FILE to qprolog clauses and add them to the database.
Returns the number of clauses read."
  (ensure-pl2lispy)
  (let* ((file (pathname file))
         (out (make-string-output-stream))
         (count (progv (list (find-symbol "*QP-MODE*" :pl2lispy)) (list t)
                  (funcall (pl2lispy-fn "TRANSLATE-TEXT") (funcall (pl2lispy-fn "SLURP") file) out
                           :name (or (pathname-name file) "program")))))
    (with-input-from-string (s (get-output-stream-string out))
      (let ((*package* (find-package :qp)) (*read-default-float-format* 'double-float))
        (loop for form = (read s nil :eof) until (eq form :eof) do (eval form))))
    count))

(defdet consult (file) (consult-pl (text-of file)) t)
