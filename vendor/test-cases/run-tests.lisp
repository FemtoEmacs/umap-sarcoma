#!/usr/bin/env sbcl --script

(load (merge-pathnames "test-cases-core.lisp" *load-truename*))

(let ((arguments (cdr sb-ext:*posix-argv*)))
  (unless (= (length arguments) 1)
    (format *error-output* "Usage: sbcl --script run-tests.lisp SUITE.lisp~%")
    (sb-ext:exit :code 2))
  (handler-case
      (progn
        (test-cases:clear-tests)
        (load (truename (first arguments)))
        (multiple-value-bind (successp passed failed assertions)
            (test-cases:run-registered-tests)
          (declare (ignore passed failed assertions))
          (sb-ext:exit :code (if successp 0 1))))
    (condition (condition)
      (format *error-output* "Unable to run suite ~A: ~A~%"
              (first arguments) condition)
      (sb-ext:exit :code 2))))

