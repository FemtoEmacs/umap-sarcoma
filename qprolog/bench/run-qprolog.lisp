;;;; run-qprolog.lisp -- time one benchmark program on qprolog, the way swi/run.pl does:
;;;;
;;;;    time = CPU(N x  \+ \+ top)  -  CPU(N x  \+ \+ dummy)
;;;;
;;;;   sbcl --noinform --dynamic-space-size 4GB --control-stack-size 512MB --non-interactive \
;;;;        --load bench/run-qprolog.lisp --eval '(run-benchmark "tak" 128)'
;;;;
;;;; Prints one CSV line  program,iterations,time,gc,load,warmup,ok  (same as run-lispy.lisp).
;;;; warmup = seconds of the first, untimed run of `top`, which pays the SBCL COMPILE cost
;;;; of every clause it uses (clauses are compiled lazily, on first call).

(in-package :cl-user)
(when (sb-ext:posix-getenv "QP_DEBUG") (push :qp-debug *features*))   ; safe, slow code

(defparameter *bench-root*
  (make-pathname :name nil :type nil :defaults (or *load-truename* *load-pathname*)))

(let ((*standard-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (load (merge-pathnames "../load.lisp" *bench-root*))))

(in-package :qp)

(defun secs (units) (/ (float units 1d0) internal-time-units-per-second))

(defun ntimes (q n)
  "N times  \\+ \\+ GOAL ; returns (values cpu-seconds gc-seconds)."
  (let ((c0 (get-internal-run-time)) (g0 sb-ext:*gc-run-time*))
    (dotimes (i n) (run-query q))
    (values (secs (- (get-internal-run-time) c0)) (secs (- sb-ext:*gc-run-time* g0)))))

(defun run-benchmark (name n &optional (dir "programs/"))
  (let* ((file (merge-pathnames (format nil "~A~A.lisp" dir name) cl-user::*bench-root*))
         (t0 (get-internal-real-time)) load warmup ok)
    (handler-case
        (progn
          (let ((*standard-output* (make-broadcast-stream)) (*qp-out* (make-broadcast-stream)))
            (handler-bind ((warning #'muffle-warning))
              (load-qp file)
              (eval '(<- (dummy)))))
          (setf load (secs (- (get-internal-real-time) t0)))
          (let ((w0 (get-internal-real-time)) (*qp-out* (make-broadcast-stream)))
            (setf ok (run-query (prepare-query '(top))))
            (setf warmup (secs (- (get-internal-real-time) w0))))
          (sb-ext:gc :full t)
          (let ((*qp-out* (make-broadcast-stream))
                (q1 (prepare-query '(\\+ (\\+ (top)))))
                (q2 (prepare-query '(\\+ (\\+ (dummy))))))
            (multiple-value-bind (t-top g-top) (ntimes q1 n)
              (sb-ext:gc :full t)
              (multiple-value-bind (t-dum g-dum) (ntimes q2 n)
                (format t "~A,~D,~,3F,~,3F,~,3F,~,3F,~A~%" name n (- t-top t-dum) (- g-top g-dum)
                        load warmup (if ok "yes" "NO"))))))
      (error (e)
        (format t "~A,~D,ERROR,,,,~A~%" name n
                (substitute #\Space #\, (substitute #\Space #\Newline (princ-to-string e))))))
    (finish-output)))
