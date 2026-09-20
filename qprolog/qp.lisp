;;;; qp.lisp -- command-line runner, used by the ./qp script.
;;;;   ./qp FILE [GOAL] [-a]
;;;; loads FILE, runs GOAL (default: top) and prints the first solution (all with -a) and the time.
(let ((*standard-output* (make-broadcast-stream)))
  (load (merge-pathnames "load.lisp" (or *load-truename* *load-pathname*))))
(in-package :qp)

(defun cli-main (args)
  (let* ((all (member "-a" args :test #'string=))
         (args (remove "-a" args :test #'string=))
         (file (first args))
         (goal-text (or (second args) "top")))
    (unless file (format t "usage: ./qp FILE [GOAL] [-a]~%  e.g. ./qp bench/programs/sieve.lisp~%       ./qp bench/programs/tak.lisp '(tak 18 12 6 ?a)'~%") (sb-ext:exit :code 2))
    (handler-case
        (let* ((*package* (find-package :qp)) (*read-default-float-format* 'double-float)
               (goal (let ((g (read-from-string goal-text))) g))
               (t0 (get-internal-real-time)))
          (load-qp file)
          (format t "loaded ~A in ~,3F s~%" file (/ (- (get-internal-real-time) t0) internal-time-units-per-second))
          (let ((t1 (get-internal-real-time)))
            (multiple-value-bind (ok sols) (if all (solve-all goal) (solve-one goal))
              (let ((secs (/ (- (get-internal-real-time) t1) internal-time-units-per-second 1.0)))
                (cond ((not ok) (format t "no  (~,3F s)~%" secs))
                      (t (if all
                             (dolist (s sols) (format t "~S~%" s))
                             (format t "~S~%" (if (and (consp sols) (null (cdr sols))) (car sols) (or sols goal))))
                         (format t "yes (~,3F s~@[, ~D solution~:P~])~%" secs (and all (length sols)))))))))
      (prolog-error (c)
        (format t "error: ~S~%" (term->lisp (prolog-error-term c)))
        (when (and (null (second args)) (search "EXISTENCE_ERROR" (princ-to-string (term->lisp (prolog-error-term c)))))
          (format t "~A defines no top/0; give a goal, e.g.  ./qp ~A '(pred arg ?x)'~%" file file))
        (sb-ext:exit :code 1))
      (error (c) (format t "error: ~A~%" c) (sb-ext:exit :code 1)))))

(let ((args (cdr sb-ext:*posix-argv*)))
  (cli-main args))
