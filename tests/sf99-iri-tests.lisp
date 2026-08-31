(load "src/sf99-iri.lisp")
(load "src/periodic-surrogate.lisp")
(load "src/sf99-model-figure.lisp")

(defparameter *sf99-coefficient-data*
  (fejer-sf99-read-data "data/sf99-iri-coefficients.sexp"))

(defparameter *sf99-oracle-data*
  (fejer-sf99-read-data "data/iri-2020-sf99-oracle.sexp"))

(test-cases:deftest official-coefficient-table-is-complete
  (test-cases:check-equal
   624
   (length (fejer-sf99-plist-get *sf99-coefficient-data* :coefficients))))

(test-cases:deftest common-lisp-port-matches-official-iri-vdrift-grid
  (let ((cases (fejer-sf99-plist-get *sf99-oracle-data* :cases)))
    (test-cases:check-equal 450 (length cases))
    (dolist (case cases)
      (let ((actual
              (fejer-sf99-drift-from-data
               *sf99-coefficient-data*
               (fejer-sf99-plist-get case :local-time)
               (fejer-sf99-plist-get case :longitude)
               (fejer-sf99-plist-get case :day)
               (fejer-sf99-plist-get case :solar-flux))))
        (test-cases:check
         (<= (fejer-abs
              (- actual (fejer-sf99-plist-get case :drift)))
             0.000005)
         "Common Lisp result agrees with compiled official VDRIFT")))))

(test-cases:deftest local-time-periodic-representations-agree
  (dolist (day '(1.0 80.0 172.0 266.0 355.0))
    (dolist (flux '(80.0 140.0 200.0))
      (test-cases:check
       (<= (fejer-abs
            (- (fejer-sf99-drift-from-data
                *sf99-coefficient-data* -0.5 283.0 day flux)
               (fejer-sf99-drift-from-data
                *sf99-coefficient-data* 23.5 283.0 day flux)))
           0.000005)
       "local time and longitude are periodic"))))

(test-cases:deftest solar-flux-clipping-is-faithful
  (test-cases:check
   (<= (fejer-abs
        (- (fejer-sf99-drift-from-data
            *sf99-coefficient-data* 19.5 283.0 172.0 20.0)
           (fejer-sf99-drift-from-data
            *sf99-coefficient-data* 19.5 283.0 172.0 75.0)))
       0.000005)
   "flux below 75 is clipped to 75")
  (test-cases:check
   (<= (fejer-abs
        (- (fejer-sf99-drift-from-data
            *sf99-coefficient-data* 19.5 283.0 172.0 400.0)
           (fejer-sf99-drift-from-data
            *sf99-coefficient-data* 19.5 283.0 172.0 230.0)))
       0.000005)
   "flux above 230 is clipped to 230"))

(test-cases:deftest model-figure-curves-come-from-sf99-port
  (let* ((dataset
           (fejer-sf99-model-figure-data *sf99-coefficient-data* 283.0 80.0))
         (series (fejer-sf99-plist-get dataset :series))
         (first-series (car series))
         (points (fejer-sf99-plist-get first-series :anchors))
         (selected (elt points 78)))
    (test-cases:check-equal 3 (length series))
    (test-cases:check-equal 97 (length points))
    (test-cases:check
     (<= (fejer-abs
          (- (fejer-second selected)
             (fejer-sf99-drift-from-data
              *sf99-coefficient-data* 19.5 283.0 80.0 80.0)))
         0.000005)
     "plotted point is calculated by the verified SF99 port")))

(test-cases:deftest sf99-fs-remains-an-independent-figure-check
  (let* ((dataset (fejer-read-dataset "data/sf99-figure-6-equinox.sexp"))
         (results (fejer-evaluate-dataset dataset))
         (provenance (fejer-plist-get dataset :provenance))
         (tolerance
           (fejer-plist-get provenance :period-boundary-uncertainty-m-per-s)))
    (dolist (result results)
      (test-cases:check
       (<= (fejer-plist-get result :maximum-error) tolerance)
       "SF99-FS visual checks remain within declared reading uncertainty"))))
