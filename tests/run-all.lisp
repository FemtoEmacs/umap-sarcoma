;;;; Portable lint-first test entry point. Run from the repository root.

(load "scripts/lint-common-lisp.lisp")

(dolist (pathname '("src/sf99-iri.lisp"
                    "src/periodic-surrogate.lisp"
                    "src/sf99-model-figure.lisp"))
  (let ((errors (fejer-cl-lint-file pathname)))
    (when errors
      (dolist (message errors)
        (format *error-output* "~A~%" message))
      (error "Common Lisp source lint failed"))))

(load "vendor/test-cases/test-cases-core.lisp")
(test-cases:clear-tests)
(load "tests/sf99-iri-tests.lisp")

(multiple-value-bind (success passed failed assertions)
    (test-cases:run-registered-tests)
  (declare (ignore passed failed assertions))
  (unless success
    (error "SF99 behavioral tests failed")))

(load "umap/build-umap.lisp")

(let ((output-path "umap/output/umap-hover-the-mouse-over.html"))
  (unless (probe-file output-path)
    (error "UMAP builder did not create ~A" output-path))
  (with-open-file (stream output-path :direction :input)
    (let ((text
            (with-output-to-string (output)
              (loop for character = (read-char stream nil nil)
                    while character do (write-char character output)))))
      (unless (and (search "Historical Jicamarca covariate neighborhoods" text)
                   (search "umap-js@1.3.3" text)
                   (search "d3@7.9.0" text)
                   (not (search "__FEJER_DATA__" text)))
        (error "Generated UMAP page failed reproducibility checks")))))

(format t "ALL PORTABILITY AND REPRODUCIBILITY TESTS PASS~%")

