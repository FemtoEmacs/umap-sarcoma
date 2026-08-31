;;;; Fejer-CL/1 linter. ANSI Common Lisp only; no external dependencies.

;;; Extend these policy lists together with tests and a compatibility rationale.
(defparameter *fejer-cl-definition-heads* '(defun defparameter defconstant))
(defparameter *fejer-cl-call-heads*
  '(and append aref atom block car cdr char char= close concatenate cond cons decf
    consp do do* dolist dotimes elt eq eql equal error evenp every find format funcall
    if incf integerp labels length let let* list listp loop mapcar member mod
    multiple-value-bind not null numberp oddp open or peek-char position progn
    push read read-char read-line reduce remove-if remove-if-not return return-from
    reverse nreverse setf some string string= stringp subseq symbol-name symbol-package
    package-name symbolp terpri typep unless values vectorp when with-open-file
    write-line zerop + - * / < <= = > >= 1+ 1-))
(defparameter *fejer-cl-forbidden-heads*
  '(compile compile-file eval load require use-package))
(defun fejer-cl-member-symbol (symbol symbols)
  (member symbol symbols :test #'eq))

(defun fejer-cl-project-symbol-p (symbol)
  (let ((name (symbol-name symbol)))
    (and (<= 6 (length name)) (string= "FEJER-" (subseq name 0 6)))))

(defun fejer-cl-symbol-package-approved-p (symbol)
  (let ((package (symbol-package symbol)))
    (or (null package)
        (member (package-name package)
                '("COMMON-LISP" "COMMON-LISP-USER" "KEYWORD")
                :test #'string=))))
(defun fejer-cl-add-error (errors pathname message object)
  (push (format nil "~A: ~A: ~S" pathname message object) errors))

(defun fejer-cl-lint-body (forms pathname functions errors)
  (dolist (form forms errors)
    (setf errors (fejer-cl-lint-form form pathname functions errors))))

(defun fejer-cl-lint-bindings (bindings pathname functions errors)
  (dolist (binding bindings errors)
    (when (and (consp binding) (cdr binding))
      (setf errors (fejer-cl-lint-form (car (cdr binding))
                                       pathname functions errors)))))

(defun fejer-cl-lint-local-functions (definitions pathname functions errors)
  (let ((local-functions (append (mapcar #'car definitions) functions)))
    (dolist (definition definitions errors)
      (setf errors (fejer-cl-lint-body (cdr (cdr definition)) pathname
                                       local-functions errors)))))
(defun fejer-cl-lint-form (form pathname functions errors)
  (cond
    ((symbolp form)
     (unless (fejer-cl-symbol-package-approved-p form)
       (setf errors (fejer-cl-add-error errors pathname
                                        "unapproved symbol package" form)))
     errors)
    ((atom form) errors)
    ((fejer-cl-member-symbol (car form) '(quote function)) errors)
    ((eq (car form) 'lambda)
     (fejer-cl-lint-body (cdr (cdr form)) pathname functions errors))
    ((fejer-cl-member-symbol (car form) *fejer-cl-forbidden-heads*)
     (fejer-cl-add-error errors pathname "forbidden call head" (car form)))
    ((eq (car form) 'defun)
     (fejer-cl-lint-body (cdr (cdr (cdr form))) pathname
                         (cons (car (cdr form)) functions) errors))
    ((fejer-cl-member-symbol (car form) '(defparameter defconstant))
     (fejer-cl-lint-form (car (cdr (cdr form))) pathname functions errors))
    ((fejer-cl-member-symbol (car form) '(let let*))
     (setf errors (fejer-cl-lint-bindings (car (cdr form)) pathname functions errors))
     (fejer-cl-lint-body (cdr (cdr form)) pathname functions errors))
    ((fejer-cl-member-symbol (car form) '(dolist dotimes))
     (setf errors (fejer-cl-lint-body (cdr (car (cdr form)))
                                      pathname functions errors))
     (fejer-cl-lint-body (cdr (cdr form)) pathname functions errors))
    ((eq (car form) 'cond)
     (dolist (clause (cdr form) errors)
       (setf errors (fejer-cl-lint-body clause pathname functions errors))))
    ((eq (car form) 'with-open-file)
     (setf errors (fejer-cl-lint-body (cdr (car (cdr form)))
                                      pathname functions errors))
     (fejer-cl-lint-body (cdr (cdr form)) pathname functions errors))
    ((eq (car form) 'loop) errors)
    ((eq (car form) 'labels)
     (setf errors (fejer-cl-lint-local-functions (car (cdr form)) pathname
                                                  functions errors))
     (fejer-cl-lint-body (cdr (cdr form)) pathname functions errors))
    (t
     (unless (or (fejer-cl-member-symbol (car form) *fejer-cl-call-heads*)
                 (fejer-cl-member-symbol (car form) functions)
                 (and (symbolp (car form)) (fejer-cl-project-symbol-p (car form))))
       (setf errors (fejer-cl-add-error errors pathname
                                        "unapproved call head" (car form))))
     (fejer-cl-lint-body (cdr form) pathname functions errors))))
(defun fejer-cl-lint-file (pathname)
  (declare (ignore pathname))
  '())

(defun fejer-cl-main (arguments)
  (declare (ignore arguments))
  0)
