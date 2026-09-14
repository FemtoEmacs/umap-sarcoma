#!/usr/bin/env -S sbcl --script
;;;; Complete sarcoma pipeline -- Prolog port of the original sarcoma-setup.x.
;;;; Requires only SBCL (loads claude-prolog/prolog-engine.lisp -- the
;;;; claude-prolog git submodule, checked out alongside this file) and a
;;;; browser to view the resulting HTML, same as the original.
;;;; Overrides: SAR_EPOCHS (200), SAR_LR (0.002d0), SBCL. (SAR_FORCE_BASE_MAP
;;;; is read by the individual stage scripts themselves, not by this
;;;; orchestrator, so it's unaffected by this port and isn't mentioned here.)
;;;; SAR_EPOCHS was 100 back when the corpus held one study out as a
;;;; validation split (see smc/pilot-search.sexp's :NO-VALIDATION-SPLIT
;;;; comment for why that was dropped). Training on all 200 records without
;;;; any held-out study makes the fitting problem harder for the same fixed
;;;; model size, and 100 epochs now plateaus around train RMSE ~1.2 instead
;;;; of fully converging; 200 epochs reaches ~0.35, with every curve
;;;; (including the previously-held-out PALETTE study) landing in a similar
;;;; error range instead of a few outliers.
;;;;
;;;; Why a Prolog port: the original is a flat sequence of run-program calls.
;;;; This version instead states the pipeline as data -- SUBSTEP/5 facts
;;;; (stage number, position within the stage, description, script,
;;;; argument template) -- and lets SETOF group and order them by stage,
;;;; instead of hand-written list bookkeeping. Argument templates use
;;;; ordinary Prolog variables where the original used LET*-computed
;;;; values (?result, ?corpus, ?model, ?html, ?epochs, ?rate); each
;;;; SUBSTEP clause's own body resolves them via ENV-VALUE, so the
;;;; "$result-style" substitution a shell script would do with variable
;;;; expansion is just unification here. This only replaces the
;;;; ORCHESTRATION layer -- every actual pipeline stage is still the exact
;;;; same external "sbcl --script <file> <args>" call the original made;
;;;; none of the underlying evidence/SMC/training/HTML-generation logic is
;;;; touched or reimplemented.

(let* ((root (make-pathname :name nil :type nil :defaults *load-truename*))
       (*default-pathname-defaults* root))
  (load (merge-pathnames "claude-prolog/prolog-engine.lisp" root)))

(defparameter *sarcoma-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *sbcl*
  (or (sb-ext:posix-getenv "SBCL") (namestring sb-ext:*runtime-pathname*)))

(defun getenv-or (name default)
  (or (sb-ext:posix-getenv name) default))
(register-callable 'getenv-or)

(defun run-external-stage (description script args)
  "Exactly the original's RUN-STAGE, as a plain Lisp function LISP-EVAL can
   call: print the banner, run SCRIPT (relative to *SARCOMA-ROOT*) via SBCL
   with ARGS, and -- on a non-zero exit -- ERROR out exactly like the
   original did, which aborts this whole script uncaught, same as before."
  (format t "~%==> ~A~%" description)
  (finish-output)
  (let* ((process (sb-ext:run-program
                    *sbcl* (append (list "--script" script) args)
                    :search t :directory *sarcoma-root*
                    :input t :output t :error t :wait t))
         (code (sb-ext:process-exit-code process)))
    (if (eql code 0)
        t
        (error "Stage ~A failed with exit code ~S." description code))))
(register-callable 'run-external-stage)

;; --- the small "environment": computed paths + env-var overrides, exactly
;;     the original's LET* bindings, just as Prolog facts instead ---
(<- (env-value epochs ?v) (lisp-eval ?v (getenv-or "SAR_EPOCHS" "200")))
(<- (env-value rate ?v) (lisp-eval ?v (getenv-or "SAR_LR" "0.002d0")))
(<- (env-value result "output/sarcoma-awrs-smc-result.sexp"))
(<- (env-value corpus "smc-trainer/corpus/sarcoma-awrs-shards/manifest.sexp"))
(<- (env-value model "smc-trainer/cl-sarcoma-awrs-model.sexp"))
(<- (env-value html "output/cl-sarcoma-awrs-preferences.html"))

;; --- the pipeline itself: (substep StageNumber PositionInStage
;;     Description Script ArgList), in the same order and with the same
;;     values as the original's six RUN-STAGE calls (stage 1 and stage 3
;;     each bundle two of the original's calls, matching the "[N/5]"
;;     numbering the original's own banner messages already implied) ---
(<- (substep 1 1 "[1/5] Prepare evidence"
             "prepare-umap-data.lisp" ("pilot-problem.sexp")))
(<- (substep 1 2 "Build full evidence map"
             "build-umap.lisp" ("pilot-problem.sexp" "output/sarcoma-full.html")))
(<- (substep 2 1 "[2/5] AWRS-SMC search"
             "awrs-smc/search-umap.lisp" ("smc/pilot-search.sexp" ?result))
    (env-value result ?result))
(<- (substep 3 1 "[3/5] Build corpus"
             "smc-trainer/build-sharded-corpus.lisp"
             (?result "smc-trainer/corpus/sarcoma-awrs-shards/" "25"))
    (env-value result ?result))
(<- (substep 3 2 "Validate corpus"
             "smc-trainer/validate-corpus.lisp" (?corpus))
    (env-value corpus ?corpus))
(<- (substep 4 1 "[4/5] Train Transformer"
             "smc-trainer/train.lisp" (?corpus ?model ?epochs ?rate))
    (env-value corpus ?corpus) (env-value model ?model)
    (env-value epochs ?epochs) (env-value rate ?rate))
(<- (substep 5 1 "[5/5] Generate formatted HTML"
             "sarcoma-specific/build-preferences-page.lisp" (?corpus ?model ?html))
    (env-value corpus ?corpus) (env-value model ?model) (env-value html ?html))

;; --- the driver: group substeps by stage (SETOF sorts by stage number,
;;     and again by position within a stage), run every stage in order,
;;     every substep within a stage in order ---
(<- (run-substeps nil) !)
(<- (run-substeps ((?i ?d ?s ?a) . ?rest))
    (lisp-eval t (run-external-stage ?d ?s ?a))
    (run-substeps ?rest))

(<- (run-stages nil) !)
(<- (run-stages (?n . ?ns))
    (setof (?i ?d ?s ?a) (substep ?n ?i ?d ?s ?a) ?subs)
    (run-substeps ?subs)
    (run-stages ?ns))

(<- (run-pipeline)
    (setof ?n (substep ?n ?i ?d ?s ?a) ?stages)
    (run-stages ?stages))

(?- (run-pipeline))
(format t "~%Done. Open: ~A~%"
        (merge-pathnames "output/cl-sarcoma-awrs-preferences.html" *sarcoma-root*))
(sb-ext:exit)
