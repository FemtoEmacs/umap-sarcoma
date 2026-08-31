;;;; Declarative figure builder for curves calculated by the SF99 model port.
;;;; Fejer-CL/1: ANSI Common Lisp, no external dependencies.

(defun fejer-sf99-model-points (coefficients longitude day solar-flux step)
  (let ((points '()) (local-time 0.0))
    (loop
      (when (> local-time 24.0) (return (nreverse points)))
      (push (list local-time
                  (fejer-sf99-drift coefficients local-time longitude
                                     day solar-flux))
            points)
      (setf local-time (+ local-time step)))))

(defun fejer-sf99-model-series (coefficients longitude day solar-flux label)
  (list :id solar-flux
        :label label
        :show-anchors :no
        :anchors (fejer-sf99-model-points coefficients longitude day
                                           solar-flux 0.25)
        :checks '()))

(defun fejer-sf99-model-figure-data (coefficient-data longitude day)
  (let ((coefficients
          (fejer-sf99-plist-get coefficient-data :coefficients)))
    (list
     :provenance
     (list :model :sf99-iri-common-lisp
           :longitude-east-degrees longitude
           :day-of-year day
           :solar-flux-values '(80.0 140.0 200.0))
     :plot
     '(:width 420 :height 245
       :plot-left 58 :plot-right 405 :plot-bottom 38 :plot-top 230
       :x-min 0 :x-max 24 :y-min -30 :y-max 55
       :x-ticks (0 4 8 12 16 20 24)
       :y-ticks (-20 0 20 40)
       :x-label "Local time (h)"
       :y-label "Vertical drift (m s$^{-1}$)"
       :sample-step 0.25)
     :series
     (list
      (fejer-sf99-model-series coefficients longitude day 80.0 "$F_{10.7}=80$")
      (fejer-sf99-model-series coefficients longitude day 140.0 "$F_{10.7}=140$")
      (fejer-sf99-model-series coefficients longitude day 200.0 "$F_{10.7}=200$")))))

(defun fejer-build-sf99-model-figure (coefficient-path output-path longitude day)
  (let* ((coefficient-data (fejer-sf99-read-data coefficient-path))
         (dataset (fejer-sf99-model-figure-data coefficient-data longitude day)))
    (fejer-render-picture dataset output-path)
    dataset))
