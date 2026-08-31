(defpackage :test-cases
  (:use :cl)
  (:export #:deftest
           #:check
           #:check-equal
           #:check-signals
           #:clear-tests
           #:run-registered-tests))

(in-package :test-cases)

(defvar *tests* nil)
(defvar *assertions-run* 0)

(define-condition assertion-failed (error)
  ((description :initarg :description :reader assertion-description))
  (:report (lambda (condition stream)
             (format stream "~A" (assertion-description condition)))))

(defun clear-tests ()
  (setf *tests* nil))

(defun register-test (name function)
  (setf *tests* (remove name *tests* :key #'car :test #'equal))
  (setf *tests* (append *tests* (list (cons name function))))
  name)

(defmacro deftest (name &body body)
  `(register-test ',name (lambda () ,@body)))

(defun record-check (success description)
  (incf *assertions-run*)
  (unless success
    (error 'assertion-failed :description description))
  t)

(defmacro check (form &optional description)
  `(record-check ,form (or ,description (format nil "Check failed: ~S" ',form))))

(defmacro check-equal (expected actual &key (test '#'equal) description)
  (let ((expected-value (gensym "EXPECTED"))
        (actual-value (gensym "ACTUAL")))
    `(let ((,expected-value ,expected)
           (,actual-value ,actual))
       (record-check
        (funcall ,test ,expected-value ,actual-value)
        (or ,description
            (format nil "Expected ~S, got ~S from ~S"
                    ,expected-value ,actual-value ',actual))))))

(defmacro check-signals (condition-type &body body)
  `(let ((signaled nil))
     (handler-case
         (progn ,@body)
       (,condition-type () (setf signaled t)))
     (record-check signaled
                   (format nil "Expected condition ~S from ~S"
                           ',condition-type ',body))))

(defun run-registered-tests (&key (stream *standard-output*))
  (let ((passed 0)
        (failed 0)
        (*assertions-run* 0))
    (dolist (entry *tests*)
      (handler-case
          (progn
            (funcall (cdr entry))
            (incf passed)
            (format stream "PASS ~A~%" (car entry)))
        (condition (condition)
          (incf failed)
          (format stream "FAIL ~A: ~A~%" (car entry) condition))))
    (format stream "tests=~D passed=~D failed=~D assertions=~D~%"
            (+ passed failed) passed failed *assertions-run*)
    (values (zerop failed) passed failed *assertions-run*)))

