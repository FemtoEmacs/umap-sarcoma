;;;; Generic periodic piecewise-linear surrogate and LaTeX picture renderer.
;;;; Fejer-CL/1: ANSI Common Lisp, no external dependencies.

(defun fejer-second (value)
  (car (cdr value)))

(defun fejer-plist-get (plist key)
  (cond
    ((null plist) nil)
    ((eq (car plist) key) (fejer-second plist))
    (t (fejer-plist-get (cdr (cdr plist)) key))))

(defun fejer-abs (value)
  (if (< value 0) (- value) value))

(defun fejer-max (left right)
  (if (> left right) left right))

(defun fejer-normalize-periodic (value minimum maximum)
  (+ minimum (mod (- value minimum) (- maximum minimum))))

(defun fejer-linear-value (x left right)
  (let* ((x-left (car left))
         (y-left (fejer-second left))
         (x-right (car right))
         (y-right (fejer-second right))
         (weight (/ (- x x-left) (- x-right x-left))))
    (+ y-left (* weight (- y-right y-left)))))

(defun fejer-periodic-value (points value minimum maximum)
  (let* ((x (fejer-normalize-periodic value minimum maximum))
         (first (car points))
         (last (car (reverse points))))
    (cond
      ((< x (car first))
       (fejer-linear-value x
                           (list (- (car last) (- maximum minimum))
                                 (fejer-second last))
                           first))
      ((>= x (car last))
       (fejer-linear-value x last
                           (list (+ (car first) (- maximum minimum))
                                 (fejer-second first))))
      (t
       (block interval
         (let ((remaining points))
           (loop
             (let ((left (car remaining))
                   (right (car (cdr remaining))))
               (when (and (<= (car left) x) (< x (car right)))
                 (return-from interval (fejer-linear-value x left right)))
               (setf remaining (cdr remaining))))))))))

(defun fejer-sample-series (series minimum maximum step)
  (let ((points (fejer-plist-get series :anchors))
        (samples '())
        (x minimum))
    (loop
      (when (> x maximum) (return (nreverse samples)))
      (push (list x (fejer-periodic-value points x minimum maximum)) samples)
      (setf x (+ x step)))))

(defun fejer-scale (value data-minimum data-maximum plot-minimum plot-maximum)
  (+ plot-minimum
     (* (/ (- value data-minimum) (- data-maximum data-minimum))
        (- plot-maximum plot-minimum))))

(defun fejer-render-segment (stream left right config)
  (let* ((x-min (fejer-plist-get config :x-min))
         (x-max (fejer-plist-get config :x-max))
         (y-min (fejer-plist-get config :y-min))
         (y-max (fejer-plist-get config :y-max))
         (plot-left (fejer-plist-get config :plot-left))
         (plot-right (fejer-plist-get config :plot-right))
         (plot-bottom (fejer-plist-get config :plot-bottom))
         (plot-top (fejer-plist-get config :plot-top))
         (x-one (fejer-scale (car left) x-min x-max plot-left plot-right))
         (y-one (fejer-scale (fejer-second left) y-min y-max plot-bottom plot-top))
         (x-two (fejer-scale (car right) x-min x-max plot-left plot-right))
         (y-two (fejer-scale (fejer-second right) y-min y-max plot-bottom plot-top)))
    (format stream "\\qbezier(~,2F,~,2F)(~,2F,~,2F)(~,2F,~,2F)~%"
            x-one y-one (/ (+ x-one x-two) 2) (/ (+ y-one y-two) 2) x-two y-two)))

(defun fejer-render-polyline (stream points config)
  (let ((remaining points))
    (loop
      (when (null (cdr remaining)) (return nil))
      (fejer-render-segment stream (car remaining) (car (cdr remaining)) config)
      (setf remaining (cdr remaining)))))

(defun fejer-render-mark (stream point config radius)
  (let ((x (fejer-scale (car point)
                        (fejer-plist-get config :x-min)
                        (fejer-plist-get config :x-max)
                        (fejer-plist-get config :plot-left)
                        (fejer-plist-get config :plot-right)))
        (y (fejer-scale (fejer-second point)
                        (fejer-plist-get config :y-min)
                        (fejer-plist-get config :y-max)
                        (fejer-plist-get config :plot-bottom)
                        (fejer-plist-get config :plot-top))))
    (format stream "\\put(~,2F,~,2F){\\circle*{~,2F}}~%" x y radius)))

(defun fejer-render-series (stream series config index)
  (let* ((step (fejer-plist-get config :sample-step))
         (samples (fejer-sample-series series
                                       (fejer-plist-get config :x-min)
                                       (fejer-plist-get config :x-max)
                                       step))
         (anchors (fejer-plist-get series :anchors))
         (checks (fejer-plist-get series :checks))
         (legend-x (+ (fejer-plist-get config :plot-left) 12))
         (legend-y (- (fejer-plist-get config :plot-top) 8 (* 12 index))))
    (format stream "\\linethickness{~,2Fpt}~%" (+ 0.35 (* index 0.25)))
    (fejer-render-polyline stream samples config)
    (when (not (eq (fejer-plist-get series :show-anchors) :no))
      (dolist (point anchors) (fejer-render-mark stream point config 1.8)))
    (dolist (point checks) (fejer-render-mark stream point config 1.0))
    (format stream "\\put(~,2F,~,2F){\\makebox(0,0)[l]{\\scriptsize ~A}}~%"
            legend-x legend-y (fejer-plist-get series :label))))

(defun fejer-render-tick (stream value horizontal config)
  (if horizontal
      (let ((x (fejer-scale value
                            (fejer-plist-get config :x-min)
                            (fejer-plist-get config :x-max)
                            (fejer-plist-get config :plot-left)
                            (fejer-plist-get config :plot-right)))
            (y (fejer-plist-get config :plot-bottom)))
        (format stream "\\put(~,2F,~,2F){\\line(0,-1){3}}~%" x y)
        (format stream "\\put(~,2F,~,2F){\\makebox(0,0)[t]{\\scriptsize ~A}}~%"
                x (- y 5) value))
      (let ((x (fejer-plist-get config :plot-left))
            (y (fejer-scale value
                            (fejer-plist-get config :y-min)
                            (fejer-plist-get config :y-max)
                            (fejer-plist-get config :plot-bottom)
                            (fejer-plist-get config :plot-top))))
        (format stream "\\put(~,2F,~,2F){\\line(-1,0){3}}~%" x y)
        (format stream "\\put(~,2F,~,2F){\\makebox(0,0)[r]{\\scriptsize ~A}}~%"
                (- x 5) y value))))

(defun fejer-render-picture (dataset pathname)
  (let* ((config (fejer-plist-get dataset :plot))
         (width (fejer-plist-get config :width))
         (height (fejer-plist-get config :height))
         (left (fejer-plist-get config :plot-left))
         (right (fejer-plist-get config :plot-right))
         (bottom (fejer-plist-get config :plot-bottom))
         (top (fejer-plist-get config :plot-top))
         (index 0))
    (with-open-file (stream pathname :direction :output :if-exists :supersede)
      (format stream "%% Generated from declarative surrogate data.~%")
      (format stream "\\setlength{\\unitlength}{1pt}~%")
      (format stream "\\begin{picture}(~A,~A)~%" width height)
      (format stream "\\put(~A,~A){\\framebox(~A,~A){}}~%"
              left bottom (- right left) (- top bottom))
      (dolist (tick (fejer-plist-get config :x-ticks))
        (fejer-render-tick stream tick t config))
      (dolist (tick (fejer-plist-get config :y-ticks))
        (fejer-render-tick stream tick nil config))
      (format stream "\\put(~,2F,~,2F){\\makebox(0,0){\\small ~A}}~%"
              (/ (+ left right) 2) (- bottom 24)
              (fejer-plist-get config :x-label))
      (format stream "\\put(~,2F,~,2F){\\rotatebox{90}{\\small ~A}}~%"
              (- left 38) (/ (+ bottom top) 2)
              (fejer-plist-get config :y-label))
      (dolist (series (fejer-plist-get dataset :series))
        (fejer-render-series stream series config index)
        (setf index (1+ index)))
      (format stream "\\end{picture}~%"))))

(defun fejer-series-error (series config)
  (let ((sum 0) (largest 0) (count 0))
    (dolist (point (fejer-plist-get series :checks))
      (let ((error (fejer-abs
                    (- (fejer-periodic-value
                        (fejer-plist-get series :anchors)
                        (car point)
                        (fejer-plist-get config :x-min)
                        (fejer-plist-get config :x-max))
                       (fejer-second point)))))
        (setf sum (+ sum error))
        (setf largest (fejer-max largest error))
        (setf count (1+ count))))
    (list :id (fejer-plist-get series :id)
          :count count
          :mae (if (zerop count) 0 (/ sum count))
          :maximum-error largest)))

(defun fejer-evaluate-dataset (dataset)
  (let ((config (fejer-plist-get dataset :plot)))
    (mapcar (lambda (series) (fejer-series-error series config))
            (fejer-plist-get dataset :series))))

(defun fejer-read-dataset (pathname)
  (with-open-file (stream pathname :direction :input)
    (read stream nil nil)))

(defun fejer-build-surrogate (data-path output-path)
  (let ((dataset (fejer-read-dataset data-path)))
    (fejer-render-picture dataset output-path)
    (fejer-evaluate-dataset dataset)))
