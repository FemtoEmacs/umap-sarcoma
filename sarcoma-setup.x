#!/usr/bin/env -S sbcl --script
;;;; Complete sarcoma pipeline -- Prolog port of the original sarcoma-setup.x, running on qprolog.
;;;; Requires only SBCL (loads qprolog/load.lisp and qprolog/lib/pipeline.lisp -- the qprolog engine,
;;;; checked out alongside this file) and a browser to view the resulting HTML, same as the original.
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
;;;; SUBSTEP clause's own body resolves them via ENV_VALUE, so the
;;;; "$result-style" substitution a shell script would do with variable
;;;; expansion is just unification here. This only replaces the
;;;; ORCHESTRATION layer -- every actual pipeline stage is still the exact
;;;; same external "sbcl --script <file> <args>" call the original made;
;;;; none of the underlying evidence/SMC/training/HTML-generation logic is
;;;; touched or reimplemented.
;;;;
;;;; The orchestration MECHANISM (launching a process, checking its exit
;;;; code, reporting a failure, grouping/ordering SUBSTEP facts into a run)
;;;; lives in qprolog/lib/pipeline.lisp, and is itself Prolog on top of
;;;; qprolog's system predicates (getenv/2, process_run/4, halt/1; see
;;;; qprolog/src/system.lisp). This file supplies only what is specific to
;;;; this pipeline: the ENV_VALUE and SUBSTEP facts below, plus the one
;;;; (run_pipeline) call.

(let* ((root (make-pathname :name nil :type nil :defaults *load-truename*))
       (*default-pathname-defaults* root))
  (load (merge-pathnames "qprolog/load.lisp" root))
  (load (merge-pathnames "qprolog/lib/pipeline.lisp" root))
  ;; where the stage scripts run and are resolved (pipeline.lisp's pipeline_root/1)
  ;; (a funcall: the QP package does not exist yet when this whole form is read)
  (funcall (intern "ADD-CLAUSE" "QP") (list 'pipeline_root (namestring root)) nil))

;; --- the small "environment": paths + env-var overrides, exactly the
;;     original's LET* bindings, just as Prolog facts instead ---
(qp:<- (env_value epochs ?v) (getenv_or "SAR_EPOCHS" "200" ?v))
(qp:<- (env_value rate ?v) (getenv_or "SAR_LR" "0.002d0" ?v))
(qp:<- (env_value result "output/sarcoma-awrs-smc-result.sexp"))
(qp:<- (env_value corpus "smc-trainer/corpus/sarcoma-awrs-shards/manifest.sexp"))
(qp:<- (env_value model "smc-trainer/cl-sarcoma-awrs-model.sexp"))
(qp:<- (env_value html "output/cl-sarcoma-awrs-preferences.html"))

;; --- the pipeline itself: (substep StageNumber PositionInStage
;;     Description Script ArgList), in the same order and with the same
;;     values as the original's six RUN-STAGE calls (stage 1 and stage 3
;;     each bundle two of the original's calls, matching the "[N/5]"
;;     numbering the original's own banner messages already implied) ---
(qp:<- (substep 1 1 "[1/5] Prepare evidence"
                "prepare-umap-data.lisp" ("pilot-problem.sexp")))
(qp:<- (substep 1 2 "Build full evidence map"
                "build-umap.lisp" ("pilot-problem.sexp" "output/sarcoma-full.html")))
(qp:<- (substep 2 1 "[2/5] AWRS-SMC search"
                "awrs-smc/search-umap.lisp" ("smc/pilot-search.sexp" ?result))
       (env_value result ?result))
(qp:<- (substep 3 1 "[3/5] Build corpus"
                "smc-trainer/build-sharded-corpus.lisp"
                (?result "smc-trainer/corpus/sarcoma-awrs-shards/" "25"))
       (env_value result ?result))
(qp:<- (substep 3 2 "Validate corpus"
                "smc-trainer/validate-corpus.lisp" (?corpus))
       (env_value corpus ?corpus))
(qp:<- (substep 4 1 "[4/5] Train Transformer"
                "smc-trainer/train.lisp" (?corpus ?model ?epochs ?rate))
       (env_value corpus ?corpus) (env_value model ?model)
       (env_value epochs ?epochs) (env_value rate ?rate))
(qp:<- (substep 5 1 "[5/5] Generate formatted HTML"
                "sarcoma-specific/build-preferences-page.lisp" (?corpus ?model ?html))
       (env_value corpus ?corpus) (env_value model ?model) (env_value html ?html))

(unless (handler-case (qp:solve-one '(run_pipeline))
          (error (c) (format t "~%Pipeline error: ~A~%" c) nil))
  (format t "~%Pipeline failed.~%")
  (sb-ext:exit :code 1))
(format t "~%Done. Open: ~A~%"
        (merge-pathnames "output/cl-sarcoma-awrs-preferences.html"
                         (make-pathname :name nil :type nil :defaults *load-truename*)))
(sb-ext:exit)
