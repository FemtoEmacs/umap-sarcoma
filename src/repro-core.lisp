;;;; Minimal support functions for the self-contained CINEMA-OT--SF-VIPN run.
;;;; ANSI Common Lisp; no external dependencies.

(defun fejer-surrogate-get (plist key)
  (cond ((null plist) nil)
        ((eq (car plist) key) (car (cdr plist)))
        (t (fejer-surrogate-get (cdr (cdr plist)) key))))

(defun fejer-sf-vipn-get (plist key)
  (fejer-surrogate-get plist key))

(defun fejer-surrogate-bin (local-time)
  (let ((edge 2.0) (index 0))
    (loop
      (when (< local-time edge) (return index))
      (setf edge (+ edge 2.0))
      (setf index (1+ index)))))

(defun fejer-surrogate-season-bin (day)
  (cond ((<= day 91) 0)
        ((<= day 182) 1)
        ((<= day 273) 2)
        (t 3)))

(defun fejer-sf-vipn-bin (observation)
  (+ (* 12 (fejer-surrogate-season-bin
             (fejer-sf-vipn-get observation :day)))
     (fejer-surrogate-bin (fejer-sf-vipn-get observation :local-time))))

(defun fejer-sf-vipn-residual (observation)
  (- (fejer-sf-vipn-get observation :observed)
     (fejer-sf-vipn-get observation :sf99)))

(defun fejer-surrogate-excluding (observations event)
  (remove-if (lambda (observation)
               (eq event (fejer-surrogate-get observation :event)))
             observations))

(defun fejer-surrogate-only (observations event)
  (remove-if-not (lambda (observation)
                   (eq event (fejer-surrogate-get observation :event)))
                 observations))
