#!/usr/bin/env -S sbcl --script
;;;; Complete sarcoma pipeline. Requires only SBCL and a browser to view HTML.
;;;; Overrides: SAR_EPOCHS (100), SAR_LR (0.002d0), SAR_FORCE_BASE_MAP (0), SBCL.
(let* ((root (make-pathname :name nil :type nil :defaults *load-truename*))
       (*default-pathname-defaults* root)
       (sbcl (or (sb-ext:posix-getenv "SBCL") (namestring sb-ext:*runtime-pathname*)))
       (epochs (or (sb-ext:posix-getenv "SAR_EPOCHS") "100"))
       (rate (or (sb-ext:posix-getenv "SAR_LR") "0.002d0"))
       (result "output/sarcoma-awrs-smc-result.sexp")
       (corpus "smc-trainer/corpus/sarcoma-awrs-shards/manifest.sexp")
       (model "smc-trainer/cl-sarcoma-awrs-model.sexp")
       (html "output/cl-sarcoma-awrs-preferences.html"))
  (labels ((run-stage (description script &rest arguments)
             (format t "~%==> ~A~%" description)
             (finish-output)
             (let* ((process (sb-ext:run-program
                              sbcl (append (list "--script" script) arguments)
                              :search t :directory root
                              :input t :output t :error t :wait t))
                    (code (sb-ext:process-exit-code process)))
               (unless (eql code 0)
                 (error "Stage ~A failed with exit code ~S." description code)))))
    (run-stage "[1/5] Prepare evidence" "prepare-umap-data.lisp" "pilot-problem.sexp")
    (run-stage "Build full evidence map" "build-umap.lisp" "pilot-problem.sexp" "output/sarcoma-full.html")
    (run-stage "[2/5] AWRS-SMC search" "awrs-smc/search-umap.lisp"
               "smc/pilot-search.sexp" result)
    (run-stage "[3/5] Build corpus" "smc-trainer/build-sharded-corpus.lisp" result "smc-trainer/corpus/sarcoma-awrs-shards/" "25")
    (run-stage "Validate corpus" "smc-trainer/validate-corpus.lisp" corpus)
    (run-stage "[4/5] Train Transformer" "smc-trainer/train.lisp" corpus model epochs rate)
    (run-stage "[5/5] Generate formatted HTML"
               "sarcoma-specific/build-preferences-page.lisp" corpus model html)
    (format t "~%Done. Open: ~A~%" (merge-pathnames html root))))
