;;;; Backward-compatible entry point for the pilot manifest.

(defparameter *run-sarcoma-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *score-umap-run-main* nil)
(load (merge-pathnames "score-umap.lisp" *run-sarcoma-root*))

(score-umap-manifest (merge-pathnames "pilot-problem.sexp"
                                      *run-sarcoma-root*))
