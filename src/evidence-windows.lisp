;;;; Evidence-curve sampling and multiscale windows. ANSI Common Lisp.

(defparameter *evidence-temporal-profile-count* 10)
(defparameter *evidence-window-width* 0.25d0)
(defparameter *evidence-window-widths* '(0.125d0 0.25d0 0.50d0))
(defparameter *evidence-survival-transform* :identity)
(defparameter *evidence-include-survival-progress* t)
(defparameter *evidence-use-typed-transforms* nil)

(defun evidence-plist (items key)
  (cond ((null items) nil)
        ((eq (car items) key) (cadr items))
        (t (evidence-plist (cddr items) key))))

(defun evidence-weibull-parameters (landmarks)
  (let* ((one (first landmarks)) (two (second landmarks))
         (time-one (first one)) (survival-one (second one))
         (time-two (first two)) (survival-two (second two))
         (shape (/ (log (/ (- (log survival-two))
                            (- (log survival-one))))
                   (log (/ time-two time-one))))
         (scale (/ time-one
                   (expt (- (log survival-one)) (/ 1d0 shape)))))
    (list shape scale)))

(defun evidence-survival (curve month)
  (case (evidence-plist curve :model)
    (:exponential-median
     (exp (- (* (log 2d0) (/ month
                              (evidence-plist curve :median-months))))))
    (:exponential-landmark
     (let* ((landmark (first (evidence-plist curve :landmarks)))
            (time (first landmark))
            (survival (second landmark))
            (rate (/ (- (log survival)) time)))
       (exp (- (* rate month)))))
    (:weibull-landmarks
     (let ((parameters
            (evidence-weibull-parameters
             (evidence-plist curve :landmarks))))
       (exp (- (expt (/ month (second parameters))
                     (first parameters))))))
    (otherwise (error "Unsupported evidence curve model."))))

(defun evidence-curve-points (curve count)
  (let ((maximum (evidence-plist curve :maximum-months)))
    (loop for index from 0 below count
          for month = (* maximum (/ index (1- count)))
          collect (list (coerce month 'double-float)
                        (evidence-survival curve month)))))

(defun evidence-trapezoid-area (values)
  (/ (loop for left in values for right in (cdr values)
           sum (/ (+ left right) 2d0))
     (1- (length values))))

(defun evidence-log10p (value)
  "Return the pancreas-style log10(1+x) transform."
  (unless (and (numberp value) (>= value 0))
    (error "LOG10(1+x) requires a nonnegative number; found ~A." value))
  (/ (log (1+ value)) (log 10d0)))

(defun evidence-cloglog (survival)
  "Boundary-protected complementary log-log transform for survival."
  (let ((bounded (max 1d-6 (min (- 1d0 1d-6) survival))))
    (log (- (log bounded)))))

(defun evidence-protected-logit (proportion)
  (let ((bounded (max 1d-6 (min (- 1d0 1d-6) proportion))))
    (log (/ bounded (- 1d0 bounded)))))

(defun evidence-transform-survival (survival)
  (case *evidence-survival-transform*
    (:identity (coerce survival 'double-float))
    (:log10p (evidence-log10p survival))
    (:cloglog (evidence-cloglog survival))
    (otherwise (error "Unsupported survival transform ~A."
                      *evidence-survival-transform*))))

(defun evidence-transformed-value (curve key)
  (let ((value (evidence-plist curve key)))
    (and value
         (cond
           ((eq key :survival-progress-delta)
            (coerce value 'double-float))
           ((and *evidence-use-typed-transforms*
                 (member key '(:pfs-hazard-ratio :os-hazard-ratio)))
            (log value))
           ((and *evidence-use-typed-transforms*
                 (member key '(:objective-response-rate
                               :disease-control-rate)))
            (evidence-protected-logit value))
           (t (evidence-log10p value))))))

(defun evidence-landmark-value (curve key month)
  (let ((point (find month (evidence-plist curve key) :key #'first :test #'=)))
    (and point (second point))))

(defparameter *evidence-optional-fields*
  '(:cohort-size :median-pfs-months :median-os-months :follow-up-months
    :objective-response-rate :disease-control-rate :time-to-response-months
    :pfs-hazard-ratio :os-hazard-ratio))

(defun evidence-effective-optional-fields ()
  (if *evidence-include-survival-progress*
      (append *evidence-optional-fields* '(:survival-progress-delta))
      *evidence-optional-fields*))

(defun evidence-mixed-features (curve)
  "Non-PFS evidence. NIL values are imputed across the pilot after assembly."
  (append
   (mapcar (lambda (key) (evidence-transformed-value curve key))
           (evidence-effective-optional-fields))
   (loop for month in '(36 60 120)
         for value = (evidence-landmark-value curve :os-landmarks month)
         collect (and value (evidence-log10p value)))))

(defun evidence-reported-fields (curve)
  (append
   (loop for key in (evidence-effective-optional-fields)
         when (evidence-plist curve key) collect key)
   (loop for month in '(36 60 120)
         when (evidence-landmark-value curve :os-landmarks month)
           collect (intern (format nil "OS-~D-MONTH" month) :keyword))))

(defun evidence-median (numbers)
  (let* ((ordered (sort (copy-list numbers) #'<))
         (count (length ordered))
         (middle (floor count 2)))
    (cond ((zerop count) 0d0)
          ((oddp count) (nth middle ordered))
          (t (/ (+ (nth (1- middle) ordered) (nth middle ordered)) 2d0)))))

(defun evidence-impute-vectors (records)
  "Median-impute for geometry only; source records retain reporting provenance."
  (let* ((width (length (getf (first records) :vector)))
         (medians
          (loop for index below width
                collect (evidence-median
                         (loop for record in records
                               for value = (nth index (getf record :vector))
                               when value collect value)))))
    (dolist (record records records)
      (setf (getf record :vector)
            (loop for value in (getf record :vector)
                  for median in medians
                  collect (if (null value) median value))))))

(defun evidence-window-records (curve curve-index)
  (declare (ignore curve-index))
  (let* ((maximum (evidence-plist curve :maximum-months))
         (curve-points (evidence-curve-points curve 41)))
    (loop for window-index from 0 below *evidence-temporal-profile-count*
          for start-fraction =
            (if (= *evidence-temporal-profile-count* 1)
                0d0
                (* (- 1d0 *evidence-window-width*)
                   (/ window-index (1- *evidence-temporal-profile-count*))))
          for end-fraction = (+ start-fraction *evidence-window-width*)
          for fractions = (list start-fraction
                                (+ start-fraction (* 0.25d0 *evidence-window-width*))
                                (+ start-fraction (* 0.50d0 *evidence-window-width*))
                                (+ start-fraction (* 0.75d0 *evidence-window-width*))
                                end-fraction)
          for values = (mapcar
                         (lambda (fraction)
                           (evidence-survival curve (* maximum fraction)))
                         fractions)
          for first-value = (first values)
          for relative = (mapcar (lambda (value) (/ value first-value)) values)
          collect
          (list :id (format nil "~A-scale-~3,'0D-window-~2,'0D"
                            (evidence-plist curve :id)
                            (round (* 1000 *evidence-window-width*))
                            window-index)
                :curve-id (string-downcase
                           (symbol-name (evidence-plist curve :id)))
                :study (evidence-plist curve :study)
                :doi (evidence-plist curve :doi)
                :sarcoma-type (evidence-plist curve :sarcoma-type)
                :histology (evidence-plist curve :histology)
                :therapy (evidence-plist curve :therapy)
                :primary-event (evidence-plist curve :primary-event)
                :survival-progress-delta
                (evidence-plist curve :survival-progress-delta)
                :endpoint (or (evidence-plist curve :endpoint)
                              "Progression-free survival")
                :cohort-size (evidence-plist curve :cohort-size)
                :window-start-months (* maximum start-fraction)
                :window-end-months (* maximum end-fraction)
                :window-scale (cond ((< *evidence-window-width* 0.20d0) "Short")
                                    ((< *evidence-window-width* 0.40d0) "Medium")
                                    (t "Long"))
                :window-survival first-value
                :local-drop (- 1d0 (car (last relative)))
                :reported-evidence (evidence-reported-fields curve)
                :curve curve-points
                :vector
                (append (mapcar #'evidence-transform-survival relative)
                        (mapcar #'evidence-log10p
                                (list (- 1d0 (car (last relative)))
                                      (evidence-trapezoid-area relative)
                                      start-fraction
                                      maximum))
                        (evidence-mixed-features curve)
                        (list (coerce (evidence-plist curve :event-code)
                                      'double-float)))))))

(defun evidence-all-window-records (curves)
  (evidence-impute-vectors
   (loop for curve in curves for curve-index from 0
         append (evidence-window-records curve curve-index))))

(defun evidence-all-multiscale-records (curves)
  (loop for width in *evidence-window-widths*
        do (setf *evidence-window-width* width)
        append (evidence-all-window-records curves)))
