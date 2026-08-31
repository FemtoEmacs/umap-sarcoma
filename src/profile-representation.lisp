;;;; Campaign-day curve profiles for tabular observations.

(defun profile-mean (records field)
  (/ (loop for record in records sum (getf record field))
     (length records)))

(defun profile-standard-deviation (records field)
  (let ((mean (profile-mean records field)))
    (sqrt (/ (loop for record in records
                   for difference = (- (getf record field) mean)
                   sum (* difference difference))
             (length records)))))

(defun profile-circular-offset (value center period)
  (let ((offset (- value center))
        (half (/ period 2d0)))
    (cond ((>= offset half) (- offset period))
          ((< offset (- half)) (+ offset period))
          (t offset))))

(defun profile-window-records (records time-field center width)
  (let ((half (/ width 2d0)))
    (remove-if-not
     (lambda (record)
       (< (abs (profile-circular-offset
                (getf record time-field) center 24d0))
          half))
     records)))

(defun profile-window-slope (records time-field signal-field center ridge)
  (let* ((mean-time
          (/ (loop for record in records
                   sum (profile-circular-offset
                        (getf record time-field) center 24d0))
             (length records)))
         (mean-signal (profile-mean records signal-field))
         (numerator 0d0)
         (denominator ridge))
    (dolist (record records (/ numerator denominator))
      (let ((time-difference
             (- (profile-circular-offset
                 (getf record time-field) center 24d0)
                mean-time))
            (signal-difference
             (- (getf record signal-field) mean-signal)))
        (incf numerator (* time-difference signal-difference))
        (incf denominator (* time-difference time-difference))))))

(defun profile-window-coverage (records time-field center width)
  (let ((offsets
         (mapcar (lambda (record)
                   (profile-circular-offset
                    (getf record time-field) center 24d0))
                 records)))
    (/ (- (reduce #'max offsets) (reduce #'min offsets)) width)))

(defun profile-groups (records fields)
  (let (groups)
    (dolist (record records (nreverse groups))
      (let* ((key (mapcar (lambda (field) (getf record field)) fields))
             (group (assoc key groups :test #'equal)))
        (if group
            (push record (cdr group))
            (push (cons key (list record)) groups))))))

(defun profile-design-row (local-time harmonics)
  (let ((angle (* 2 pi (/ local-time 24d0))))
    (cons 1d0
          (loop for harmonic from 1 to harmonics append
            (list (sin (* harmonic angle))
                  (cos (* harmonic angle)))))))

(defun profile-solve-linear-system (matrix right)
  (let* ((size (length right))
         (augmented (make-array (list size (1+ size))
                                :element-type 'double-float)))
    (loop for row below size do
      (loop for column below size do
        (setf (aref augmented row column) (aref matrix row column)))
      (setf (aref augmented row size) (aref right row)))
    (loop for pivot below size do
      (let ((best pivot))
        (loop for row from (1+ pivot) below size do
          (when (> (abs (aref augmented row pivot))
                   (abs (aref augmented best pivot)))
            (setf best row)))
        (loop for column from pivot to size do
          (rotatef (aref augmented pivot column)
                   (aref augmented best column))))
      (let ((divisor (aref augmented pivot pivot)))
        (when (< (abs divisor) 1d-12)
          (error "Curve-profile harmonic system is singular."))
        (loop for column from pivot to size do
          (setf (aref augmented pivot column)
                (/ (aref augmented pivot column) divisor))))
      (loop for row below size unless (= row pivot) do
        (let ((factor (aref augmented row pivot)))
          (loop for column from pivot to size do
            (decf (aref augmented row column)
                  (* factor (aref augmented pivot column)))))))
    (loop for row below size collect (aref augmented row size))))

(defun profile-harmonic-coefficients
    (records time-field signal-field harmonics ridge)
  (let* ((size (1+ (* 2 harmonics)))
         (normal (make-array (list size size)
                             :element-type 'double-float
                             :initial-element 0d0))
         (right (make-array size :element-type 'double-float
                                 :initial-element 0d0)))
    (dolist (record records)
      (let ((design (profile-design-row (getf record time-field) harmonics))
            (response (getf record signal-field)))
        (loop for row below size do
          (incf (aref right row) (* (nth row design) response))
          (loop for column below size do
            (incf (aref normal row column)
                  (* (nth row design) (nth column design)))))))
    (loop for index below size do
      (incf (aref normal index index) ridge))
    (profile-solve-linear-system normal right)))

(defun profile-record (records specification)
  (let* ((first (car records))
         (event (getf first :event))
         (day (getf first :day))
         (harmonics (or (getf specification :harmonics) 2))
         (ridge (or (getf specification :ridge) 1d-6))
         (time-field (or (getf specification :time-field) :local-time))
         (signals (getf specification :signals))
         (coefficients
          (loop for signal in signals append
            (profile-harmonic-coefficients
             records time-field signal harmonics ridge)))
         (f107 (profile-mean records :f107))
         (uncertainty (profile-mean records :measurement-error))
         (season (* 2 pi (/ day 365.25d0)))
         (effects (remove nil (mapcar (lambda (record) (getf record :effect))
                                      records)))
         (support (every (lambda (record) (getf record :support)) records)))
    (list :id (format nil "~A-day-~D" event day)
          :event event
          :day day
          :observations (length records)
          :f107 f107
          :mean-observed (profile-mean records :observed)
          :mean-sf99 (profile-mean records :sf99)
          :mean-residual (profile-mean records :residual)
          :mean-uncertainty uncertainty
          :effect (and effects (/ (reduce #'+ effects) (length effects)))
          :support support
          :vector (append coefficients
                          (list f107 uncertainty (sin season) (cos season))))))

(defun profile-window-record (records specification center width)
  (let* ((first (car records))
         (event (getf first :event))
         (day (getf first :day))
         (time-field (or (getf specification :time-field) :local-time))
         (ridge (or (getf specification :ridge) 1d-6))
         (f107 (profile-mean records :f107))
         (uncertainty (profile-mean records :measurement-error))
         (season (* 2 pi (/ day 365.25d0)))
         (local-time (* 2 pi (/ center 24d0)))
         (effects
          (remove nil
                  (mapcar (lambda (record) (getf record :effect)) records)))
         (support (every (lambda (record) (getf record :support)) records))
         (coverage
          (profile-window-coverage records time-field center width))
         (observed-mean (profile-mean records :observed))
         (sf99-mean (profile-mean records :sf99))
         (residual-mean (profile-mean records :residual))
         (vector
          (list observed-mean
                (profile-standard-deviation records :observed)
                (profile-window-slope
                 records time-field :observed center ridge)
                sf99-mean
                (profile-standard-deviation records :sf99)
                (profile-window-slope records time-field :sf99 center ridge)
                residual-mean
                (profile-standard-deviation records :residual)
                f107 uncertainty
                (sin season) (cos season)
                (sin local-time) (cos local-time)
                width)))
    (list :id (format nil "~A-day-~D-lt-~,1F" event day center)
          :event event
          :day day
          :local-time-center center
          :window-width width
          :observations (length records)
          :coverage coverage
          :f107 f107
          :mean-observed observed-mean
          :mean-sf99 sf99-mean
          :mean-residual residual-mean
          :mean-uncertainty uncertainty
          :effect (and effects (/ (reduce #'+ effects) (length effects)))
          :support support
          :vector vector)))

(defun profile-window-centers (window)
  (let ((start (or (getf window :start) 0d0))
        (end (or (getf window :end) 24d0))
        (step (or (getf window :step) 2d0)))
    (loop for center from start below end by step collect center)))

(defun profile-windowed-records (records specification window)
  (let ((fields (or (getf specification :group-fields) '(:event :day)))
        (time-field (or (getf specification :time-field) :local-time))
        (widths (or (getf window :widths)
                    (list (or (getf window :width) 4d0))))
        (minimum (or (getf window :minimum-observations) 8)))
    (loop for group in (profile-groups records fields) append
      (loop for width in widths append
        (loop for center in (profile-window-centers window)
              for selected = (profile-window-records
                              (cdr group) time-field center width)
              when (>= (length selected) minimum)
                collect (profile-window-record
                         selected specification center width))))))

(defun profile-records (records specification)
  (let ((window (getf specification :window)))
    (if window
        (profile-windowed-records records specification window)
        (let ((fields
               (or (getf specification :group-fields) '(:event :day))))
          (mapcar (lambda (group)
                    (profile-record (cdr group) specification))
                  (profile-groups records fields))))))
