;;;; Compatibility name for manifest-driven UMAP data preparation.

(defparameter *build-molecdim-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(load (merge-pathnames "prepare-umap-data.lisp" *build-molecdim-root*))
