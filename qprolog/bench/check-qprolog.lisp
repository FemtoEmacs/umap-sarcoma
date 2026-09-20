;;;; check-qprolog.lisp -- differential test: run check/NAME.queries on qprolog and print
;;;; every solution in the canonical format of ../p99/swi/driver.pl, for diffing against
;;;; SWI-Prolog's output (bench/out/check-NAME.swi).
;;;;
;;;;   sbcl --noinform --non-interactive --load bench/check-qprolog.lisp \
;;;;        --eval '(qp::run-check "tak" "programs/tak.lisp" "/path/check/tak.queries")'
(in-package :cl-user)
(when (sb-ext:posix-getenv "QP_DEBUG") (push :qp-debug *features*))   ; safe, slow code
(defparameter *bench-root* (make-pathname :name nil :type nil :defaults (or *load-truename* *load-pathname*)))
(let ((*standard-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (load (merge-pathnames "../load.lisp" *bench-root*))
    (load (merge-pathnames "pl2lispy.lisp" *bench-root*))))

(in-package :qp)

(defun canon (term table stream)
  (let ((x (deref term)))
    (cond ((pv-p x) (format stream "_~D" (or (gethash x table) (setf (gethash x table) (hash-table-count table)))))
          ((null x) (write-string "nil" stream))
          ((consp x)
           (write-char #\( stream)
           (loop (canon (car x) table stream)
                 (let ((tl (deref (cdr x))))
                   (cond ((null tl) (return))
                         ((consp tl) (write-char #\Space stream) (setq x tl))
                         (t (write-string " . " stream) (canon tl table stream) (return)))))
           (write-char #\) stream))
          ((simple-vector-p x)
           (write-char #\( stream)
           (canon (svref x 0) table stream)
           (loop for i from 1 below (length x) do (write-char #\Space stream) (canon (svref x i) table stream))
           (write-char #\) stream))
          ((symbolp x) (write-string (string-downcase (symbol-name x)) stream))
          ((floatp x) (let ((*read-default-float-format* 'double-float)) (format stream "~A" (coerce x 'double-float))))
          (t (format stream "~A" x)))))

(defun canon-solution (vals)
  (if (null vals)
      "yes"
      (let ((table (make-hash-table :test 'eq)))
        (with-output-to-string (s)
          (loop for (v . more) on vals do (canon v table s) (when more (write-string " | " s)))))))

(defun run-one-query (text)
  (format t "?- ~A~%" text)
  (multiple-value-bind (goal-text vars)
      (handler-case (pl2lispy:translate-query text :qp t) (error () (values nil nil)))
    (if (null goal-text)
        (format t "  SYNTAX-ERROR~%")
        (let* ((goal (let ((*package* (find-package :qp))) (read-from-string goal-text)))
               (syms (let ((*package* (find-package :qp))) (mapcar #'read-from-string vars)))
               (result (handler-case (sb-ext:with-timeout 5 (solve-collect goal syms 101))
                         (sb-ext:timeout () :abort)
                         (storage-condition () :abort)
                         (error () :error))))
          (cond ((eq result :abort) (format t "  ABORT~%"))
                ((eq result :error) (format t "  ERROR~%"))
                ((null result) (format t "  no~%"))
                (t (loop for sol in result for i from 1 to 100
                         do (format t "  ~D: ~A~%" i (canon-solution sol)))
                   (when (> (length result) 100) (format t "  ...more~%"))))))
    (finish-output)))

(defun run-check (program-file queries-file)
  (let ((*standard-output* (make-broadcast-stream)) (*qp-out* (make-broadcast-stream)))
    (handler-bind ((warning #'muffle-warning)) (load-qp program-file)))
  (with-open-file (in queries-file)
    (loop for line = (read-line in nil) while line
          do (let ((s (string-trim '(#\Space #\Tab #\Return) line)))
               (unless (or (string= s "") (char= (char s 0) #\%))
                 (let ((*qp-out* (make-broadcast-stream))) (run-one-query (substitute #\Space #\Tab s))))))))
