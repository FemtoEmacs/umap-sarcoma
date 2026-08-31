;;;; Build leave-campaign-out CINEMA-OT effect annotations for the UMAP.

(defparameter *umap-causal-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defun umap-causal-path (relative) (merge-pathnames relative *umap-causal-directory*))

(load (umap-causal-path "src/repro-core.lisp"))

(load (umap-causal-path "src/fejer-cinema-ot.lisp"))

(defun umap-causal-events (observations)
  (let ((events 'nil))
    (dolist (observation observations (nreverse events))
      (let ((event (fejer-sf-vipn-get observation :event)))
        (unless (member event events) (push event events))))))

(defun umap-causal-models (observations events)
  (let ((models 'nil))
    (dolist (event events models)
      (push
       (cons event
             (fejer-cinema-effects (fejer-surrogate-excluding observations event)))
       models))))

(defun umap-causal-record (observation models)
  (let* ((model (cdr (assoc (fejer-sf-vipn-get observation :event) models)))
         (effects (fejer-sf-vipn-get model :effects))
         (supported (not (null effects))))
    (list :effect
          (if supported
              (fejer-cinema-bin-effect effects (fejer-sf-vipn-bin observation))
              nil)
          :support supported :high-count (fejer-sf-vipn-get model :high-count)
          :low-count (fejer-sf-vipn-get model :low-count))))

(defun build-causal-effects ()
  (let* ((input
          (with-open-file (stream (umap-causal-path "data/observations.sexp"))
            (read stream nil nil)))
         (observations (fejer-sf-vipn-get input :records))
         (events (umap-causal-events observations))
         (models (umap-causal-models observations events))
         (records
          (mapcar (lambda (observation) (umap-causal-record observation models))
                  observations))
         (output-path (umap-causal-path "data/causal-effects.sexp")))
    (with-open-file
        (stream output-path :direction :output :if-exists :supersede :if-does-not-exist
         :create)
      (write
       (list :method :cinema-ot-sf-vipn :estimand
             :high-minus-low-f107-effect-on-sf99-residual :high-threshold
             *fejer-cinema-high-flux* :low-threshold *fejer-cinema-low-flux*
             :validation :leave-campaign-out :records records)
       :stream stream :pretty t)
      (terpri stream))
    (format t "Wrote ~A with ~D causal annotations.~%" output-path (length records))))

(build-causal-effects)
