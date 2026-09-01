;;;; Complete dependency-free Common Lisp test entry point.

(load "vendor/test-cases/test-cases-core.lisp")
(test-cases:clear-tests)
(load "tests/v-measure-tests.lisp")
(load "tests/common-lisp-umap-tests.lisp")
(load "tests/preparation-tests.lisp")

(multiple-value-bind (success passed failed assertions)
    (test-cases:run-registered-tests)
  (declare (ignore passed failed assertions))
  (unless success
    (error "Common Lisp behavioral tests failed")))

;; Project-specific evidence and general manifest-builder tests.
(load "tests/evidence-umap-tests.lisp")
(load "tests/general-umap-tests.lisp")

;; Preserve the historical Jicamarca example as an independent generality
;; check for the browser-side UMAP builder.
(load "umap/build-umap.lisp")
(let ((output-path "umap/output/umap-hover-the-mouse-over.html"))
  (unless (probe-file output-path)
    (error "Jicamarca example did not create ~A." output-path))
  (with-open-file (stream output-path :direction :input)
    (let ((text
            (with-output-to-string (output)
              (loop for character = (read-char stream nil nil)
                    while character do (write-char character output)))))
      (unless (and (search "Historical Jicamarca covariate neighborhoods" text)
                   (search "umap-js@1.3.3" text)
                   (search "d3@7.9.0" text)
                   (not (search "__FEJER_DATA__" text)))
        (error "Generated Jicamarca example failed reproducibility checks")))))

(format t "ALL UMAP-SARCOMA TESTS PASS~%")
