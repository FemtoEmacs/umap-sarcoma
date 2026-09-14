#!/usr/bin/env -S sbcl --script
;;;; Sweep candidate :SMC-SEED values through the AWRS-SMC search stage only
;;;; (no corpus build, no Transformer training -- this is the ~15-20 second
;;;; step, not the full multi-minute pipeline) and report, for each seed,
;;;; whether chondrosarcoma-ivosidenib (Tap et al. 2020) still lands in the
;;;; same DBSCAN cluster as the two Desmoid-tumor curves (Gounder et al.
;;;; 2018) at that run's own automatic epsilon.
;;;;
;;;; This exists because a rebuild on this machine reproducibly (3/3 runs)
;;;; put chondrosarcoma-ivosidenib within 0.0776 standardized units of the
;;;; Desmoid cluster -- almost as close as points *within* that cluster sit
;;;; to each other (0.0115) -- even though the required features
;;;; (EVENT-CODE, SURVIVAL-NOT-REPORTED) were selected. No epsilon threshold
;;;; fixes that after the fact (see PAZOPANIB-PLACEBO-CLUSTER-MERGE.md); the
;;;; only lever left to try is whether a *different* AWRS-SMC particle --
;;;; i.e. a different :SMC-SEED -- lands on a feature subset whose embedding
;;;; keeps them apart on THIS machine's floating-point path.
;;;;
;;;; Usage: sbcl --script seed-separation-sweep.lisp [seed seed seed ...]
;;;; With no arguments, sweeps a built-in default list of candidates.
;;;; Run this from the repository root (it loads files by relative path).

(defparameter *sweep-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defparameter *awrs-umap-run-main* nil)   ; prevent awrs-smc/search-umap.lisp's
                                          ; own (when ... (awrs-search-main))
                                          ; from firing on load
(load (merge-pathnames "awrs-smc/search-umap.lisp" *sweep-root*))
(load (merge-pathnames "src/embedding-clusters.lisp" *sweep-root*))

(defparameter *base-search-path*
  (merge-pathnames "smc/pilot-search.sexp" *sweep-root*))
(defparameter *windows-path*
  (merge-pathnames "data/pilot-windows.sexp" *sweep-root*))

(defun read-curve-ids (path count)
  (let* ((*read-default-float-format* 'double-float)
         (form (with-open-file (s path) (read s)))
         (records (getf form :records)))
    (loop for record in records for i below count collect (getf record :curve-id))))

(defparameter *curve-ids* (read-curve-ids *windows-path* 200))

(defun read-form-verbatim (path)
  (let ((*read-default-float-format* 'double-float))
    (with-open-file (s path) (read s))))

(defun write-form-verbatim (form path)
  (with-open-file (stream path :direction :output :if-exists :supersede
                               :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-length* nil) (*print-level* nil))
      (prin1 form stream) (terpri stream))))

(defun search-spec-with-seed (base-form seed)
  "Return a copy of BASE-FORM's top-level plist with :SEARCH's :SMC-SEED replaced."
  (let* ((search-settings (copy-list (getf base-form :search)))
         (new-form (copy-list base-form)))
    (setf (getf search-settings :smc-seed) seed)
    (setf (getf new-form :search) search-settings)
    new-form))

(defun chondro-desmoid-separation (coordinates minimum-points)
  (let* ((standardized (embedding-standardized-coordinates coordinates))
         (chondro-rows (loop for i below 200
                              when (string= (nth i *curve-ids*) "chondrosarcoma-ivosidenib")
                                collect i))
         (desmoid-rows (loop for i below 200
                              when (member (nth i *curve-ids*)
                                           '("desmoid-sorafenib" "desmoid-placebo")
                                           :test #'string=)
                                collect i))
         (min-distance
           (loop for c in chondro-rows minimize
                 (loop for d in desmoid-rows minimize
                       (embedding-distance standardized c d))))
         (automatic (embedding-knee-epsilon standardized minimum-points))
         (assignments (embedding-dbscan standardized automatic minimum-points))
         (cluster-count (1+ (loop for v across assignments maximize v)))
         (chondro-clusters (remove-duplicates
                             (mapcar (lambda (row) (aref assignments row)) chondro-rows)))
         (desmoid-clusters (remove-duplicates
                             (mapcar (lambda (row) (aref assignments row)) desmoid-rows)))
         (mixed (intersection (remove -1 chondro-clusters)
                              (remove -1 desmoid-clusters))))
    (list :min-distance min-distance :automatic-epsilon automatic
          :cluster-count cluster-count :mixed (and mixed t))))

(defun try-seed (seed)
  (let* ((base-form (read-form-verbatim *base-search-path*))
         (variant-form (search-spec-with-seed base-form seed))
         (variant-path (merge-pathnames
                        (format nil "smc/.seed-sweep-~A.sexp" seed) *sweep-root*))
         (result-path (merge-pathnames
                       (format nil "/tmp/seed-sweep-result-~A.sexp" seed))))
    (write-form-verbatim variant-form variant-path)
    (unwind-protect
         (let* ((minimum-points (or (getf (getf variant-form :search) :minimum-points) 5))
                (output-path (awrs-search-umap variant-path result-path))
                (result (read-form-verbatim output-path))
                (best (getf result :best))
                (coordinates (getf best :coordinates)))
           (append (list :seed seed :quality (getf best :quality))
                   (chondro-desmoid-separation coordinates minimum-points)))
      (ignore-errors (delete-file variant-path)))))

(defparameter *default-seeds*
  '(20260908 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
    20260901 20260902 20260903 20260904 20260905 20260906 20260907 20260909 20260910))

(let ((seeds (or (mapcar #'parse-integer (cdr sb-ext:*posix-argv*)) *default-seeds*)))
  (format t "~%Sweeping ~D seed(s) through the AWRS-SMC search stage only~%" (length seeds))
  (format t "(no corpus build, no training -- run sarcoma-setup.x separately once~%")
  (format t "you've picked a seed to commit to).~%~%")
  (format t "~8A ~10A ~8A ~6A  ~A~%" "seed" "quality" "eps" "#clus" "chondro/desmoid mixed?")
  (let ((clean '()))
    (dolist (seed seeds)
      (handler-case
          (let ((report (try-seed seed)))
            (format t "~8A ~10,4F ~8,4F ~6D  ~A (min dist ~,4F)~%"
                    (getf report :seed) (getf report :quality)
                    (getf report :automatic-epsilon) (getf report :cluster-count)
                    (if (getf report :mixed) "YES" "no")
                    (getf report :min-distance))
            (unless (getf report :mixed) (push seed clean)))
        (error (condition)
          (format t "~8A  ERROR: ~A~%" seed condition))))
    (format t "~%Seeds where chondrosarcoma-ivosidenib did NOT land with Desmoid: ~A~%"
            (or (nreverse clean) "none"))
    (format t "Among those, prefer the one(s) with the highest quality score above,~%")
    (format t "then edit smc/pilot-search.sexp's :SMC-SEED to that value and run~%")
    (format t "./sarcoma-setup.x for the full rebuild.~%")))
