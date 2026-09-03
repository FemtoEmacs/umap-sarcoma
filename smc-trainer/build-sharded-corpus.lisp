;;;; Build the canonical corpus directly as multiple record-stream shards.

(defparameter *direct-shard-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *parametric-corpus-run-main* nil)
(load (merge-pathnames "build-corpus.lisp" *direct-shard-directory*))
(defparameter *shard-corpus-run-main* nil)
(load (merge-pathnames "shard-corpus.lisp" *direct-shard-directory*))

(defun build-sharded-parametric-corpus (result output-directory record-limit)
  "Build a temporary record stream, shard it, and always remove the temporary file."
  (let* ((directory (shard-output-directory output-directory))
         (temporary (merge-pathnames ".building-stream.sexp" directory)))
    (ensure-directories-exist temporary)
    (unwind-protect
         (progn
           (build-parametric-umap-corpus result temporary)
           (shard-corpus temporary directory :record-limit record-limit))
      (when (probe-file temporary) (delete-file temporary)))))

(let ((arguments (cdr sb-ext:*posix-argv*)))
  (unless (<= 2 (length arguments) 3)
    (error "Usage: sbcl --script smc-trainer/build-sharded-corpus.lisp AWRS-RESULT OUTPUT-DIRECTORY [RECORD-LIMIT]"))
  (build-sharded-parametric-corpus
   (first arguments) (second arguments)
   (if (third arguments) (parse-integer (third arguments)) 25)))
