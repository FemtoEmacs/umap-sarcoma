(defparameter *prepare-umap-run-main* nil)
(load "prepare-umap-data.lisp")

(test-cases:deftest manifest-drives-evidence-preparation
  (prepare-umap-data "tests/fixtures/preparation-problem.sexp")
  (let* ((result (prepare-umap-read "tests/tmp/preparation-records.sexp"))
         (records (getf result :records)))
    (test-cases:check-equal 'fixture-windows/1 (getf result :schema))
    (test-cases:check-equal 2 (length records))
    (test-cases:check-equal 22 (length (getf (first records) :vector)))
    (test-cases:check-equal "Fixture sarcoma"
                            (getf (first records) :sarcoma-type)
                            :test #'string=)))

(test-cases:deftest manifest-booleans-are-explicit
  (test-cases:check (prepare-umap-boolean 'true nil))
  (test-cases:check (not (prepare-umap-boolean 'false t)))
  (test-cases:check-signals error (prepare-umap-boolean 'perhaps nil)))
