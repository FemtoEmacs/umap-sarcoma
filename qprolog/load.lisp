;;;; load.lisp -- load qprolog.   (load "load.lisp")   then (qp::load-qp "prog.lisp")
(let ((here (make-pathname :name nil :type nil :defaults (or *load-truename* *load-pathname*)))
      (*standard-output* (if (member :qp-verbose *features*) *standard-output* (make-broadcast-stream))))
  (handler-bind ((warning #'muffle-warning))
    (dolist (f '("src/package" "src/machine" "src/terms" "src/database" "src/compiler"
                 "src/runtime" "src/builtins" "src/system" "src/consult" "lib/library"))
      (load (merge-pathnames (concatenate 'string f ".lisp") here)))))
