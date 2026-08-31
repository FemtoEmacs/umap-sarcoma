;;;; Faithful Common Lisp port of the SF99 VDRIFT routine retained in IRI-2020.
;;;; Fejer-CL/1: ANSI Common Lisp, no external dependencies.

(defparameter *fejer-sf99-time-knots*
  '(0.0 2.75 4.75 5.50 6.25 7.25 10.00 14.00 17.25 18.00
    18.75 19.75 21.00 24.00 26.75 28.75 29.50 30.25 31.25 34.00
    38.00 41.25 42.00 42.75 43.75 45.00 48.00 50.75 52.75 53.50
    54.25 55.25 58.00 62.00 65.25 66.00 66.75 67.75 69.00 72.00))

(defparameter *fejer-sf99-longitude-knots*
  '(0.0 10.0 100.0 190.0 200.0 250.0 280.0 310.0
    360.0 370.0 460.0 550.0 560.0 610.0 640.0 670.0
    720.0 730.0 820.0 910.0 920.0 970.0 1000.0 1030.0 1080.0))

(defun fejer-sf99-read-data (pathname)
  (with-open-file (stream pathname :direction :input)
    (read stream nil nil)))

(defun fejer-sf99-plist-get (plist key)
  (cond
    ((null plist) nil)
    ((eq (car plist) key) (car (cdr plist)))
    (t (fejer-sf99-plist-get (cdr (cdr plist)) key))))

(defun fejer-sf99-square (value)
  (* value value))

(defun fejer-sf99-exp-small (value)
  (let ((term 1.0) (sum 1.0) (index 1))
    (loop
      (when (> index 18) (return sum))
      (setf term (* term (/ value index)))
      (setf sum (+ sum term))
      (setf index (1+ index)))))

(defun fejer-sf99-exp (value)
  (let ((scaled value) (halvings 0))
    (loop
      (when (>= scaled -0.5) (return nil))
      (setf scaled (/ scaled 2.0))
      (setf halvings (1+ halvings)))
    (let ((result (fejer-sf99-exp-small scaled)) (index 0))
      (loop
        (when (= index halvings) (return result))
        (setf result (* result result))
        (setf index (1+ index))))))

(defun fejer-sf99-basis (basis-index value knots period)
  (let ((x value)
        (basis (list 0.0 0.0 0.0 0.0 0.0))
        (order 4))
    (when (< x (elt knots basis-index))
      (setf x (+ x period)))
    (let ((offset 0))
      (loop
        (when (= offset order) (return nil))
        (let ((knot-index (+ basis-index offset)))
          (setf (elt basis offset)
                (if (and (>= x (elt knots knot-index))
                         (< x (elt knots (1+ knot-index))))
                    1.0 0.0)))
        (setf offset (1+ offset))))
    (let ((degree 2))
      (loop
        (when (> degree order) (return nil))
        (let ((offset 0))
          (loop
            (when (> offset (- order degree)) (return nil))
            (let* ((knot-index (+ basis-index offset))
                   (left (* (/ (- x (elt knots knot-index))
                               (- (elt knots (+ knot-index degree -1))
                                  (elt knots knot-index)))
                            (elt basis offset)))
                   (right (* (/ (- (elt knots (+ knot-index degree)) x)
                                (- (elt knots (+ knot-index degree))
                                   (elt knots (1+ knot-index))))
                             (elt basis (1+ offset)))))
              (setf (elt basis offset) (+ left right)))
            (setf offset (1+ offset))))
        (setf degree (1+ degree))))
    (car basis)))

(defun fejer-sf99-season-functions (day solar-flux longitude)
  (let ((flux solar-flux) (corrected-flux solar-flux)
        (center 0.0) (sigma 1.0)
        (summer 0.0) (winter 0.0) (equinox 0.0))
    (when (<= flux 75.0) (setf flux 75.0))
    (when (>= flux 230.0) (setf flux 230.0))
    (setf corrected-flux flux)
    (when (and (>= day 120.0) (<= day 240.0))
      (setf center 170.0)
      (setf sigma 60.0))
    (when (or (<= day 60.0) (>= day 300.0))
      (setf center 170.0)
      (setf sigma 40.0))
    (when (and (<= flux 95.0) (not (= center 0.0)))
      (let ((gaussian
              (fejer-sf99-exp
               (* -0.5 (/ (fejer-sf99-square (- longitude center))
                           (fejer-sf99-square sigma))))))
        (setf corrected-flux (+ (* gaussian 95.0)
                                (* (- 1.0 gaussian) flux)))))
    (when (and (>= day 135.0) (<= day 230.0)) (setf summer 1.0))
    (when (or (<= day 45.0) (>= day 320.0)) (setf winter 1.0))
    (when (or (and (> day 75.0) (< day 105.0))
              (and (> day 260.0) (< day 290.0)))
      (setf equinox 1.0))
    (when (and (>= day 45.0) (<= day 75.0))
      (setf winter (- 1.0 (/ (- day 45.0) 30.0)))
      (setf equinox (- 1.0 winter)))
    (when (and (>= day 105.0) (<= day 135.0))
      (setf equinox (- 1.0 (/ (- day 105.0) 30.0)))
      (setf summer (- 1.0 equinox)))
    (when (and (>= day 230.0) (<= day 260.0))
      (setf summer (- 1.0 (/ (- day 230.0) 30.0)))
      (setf equinox (- 1.0 summer)))
    (when (and (>= day 290.0) (<= day 320.0))
      (setf equinox (- 1.0 (/ (- day 290.0) 30.0)))
      (setf winter (- 1.0 equinox)))
    (list summer winter equinox
          (* (- corrected-flux 140.0) summer)
          (* (- corrected-flux 140.0) winter)
          (* (- flux 140.0) equinox))))

(defun fejer-sf99-drift (coefficients local-time longitude day solar-flux)
  (let ((functions (fejer-sf99-season-functions day solar-flux longitude))
        (drift 0.0)
        (time-index 1))
    (loop
      (when (> time-index 13) (return drift))
      (let ((longitude-index 1))
        (loop
          (when (> longitude-index 8) (return nil))
          (let* ((coefficient-block (+ (* 8 (1- time-index)) longitude-index))
                 (basis (* (fejer-sf99-basis time-index local-time
                                               *fejer-sf99-time-knots* 24.0)
                           (fejer-sf99-basis longitude-index longitude
                                               *fejer-sf99-longitude-knots* 360.0)))
                 (function-index 1))
            (loop
              (when (> function-index 6) (return nil))
              (let ((coefficient-index
                      (+ (* 6 (1- coefficient-block)) (1- function-index))))
                (setf drift
                      (+ drift (* basis
                                  (elt functions (1- function-index))
                                  (elt coefficients coefficient-index)))))
              (setf function-index (1+ function-index))))
          (setf longitude-index (1+ longitude-index))))
      (setf time-index (1+ time-index)))))

(defun fejer-sf99-drift-from-data (coefficient-data local-time longitude day solar-flux)
  (fejer-sf99-drift
   (fejer-sf99-plist-get coefficient-data :coefficients)
   local-time longitude day solar-flux))
