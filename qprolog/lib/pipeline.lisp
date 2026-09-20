;;;; pipeline.lisp -- a reusable "run an external pipeline" library, the qprolog port of
;;;; claude-prolog/pipeline.lisp.  Load it after qprolog:  (qp::load-qp "qprolog/lib/pipeline.lisp")
;;;;
;;;; A consuming script supplies
;;;;   1. (pipeline_root "/dir/") -- a fact: the directory stage scripts run in.  Add it from Lisp:
;;;;        (qp::add-clause (list 'pipeline_root (namestring root)) nil)
;;;;      (calling RUN-PIPELINE without it is an existence_error on pipeline_root/1 -- a loud failure);
;;;;   2. (substep Stage Position Description Script ArgList) -- the pipeline's content;
;;;;   3. one goal:  (run_pipeline)
;;;; Each script runs as   SBCL --script Script Args...   in the pipeline root, where SBCL is the
;;;; environment variable SBCL if set, else this process's own sbcl binary.  A stage that exits
;;;; non-zero stops the pipeline: the message "Stage D failed with exit code N." is printed and the
;;;; process exits with status 1.
;;;;
;;;; Built on the system predicates (getenv/2, getenv_or/3, current_executable/1, process_run/4, halt/1) --
;;;; the decisions are all Prolog: which clause matches the exit code IS the success/failure test.
(in-package :qp)

(let ((*loading-library* t))
  (dolist (form
           '((<- (pipeline_sbcl ?b) (getenv "SBCL" ?b) !)
             (<- (pipeline_sbcl ?b) (current_executable ?b))

             (<- (announce_stage ?description) (format "~n==> ~a~n" (?description)))

             (<- (run_stage ?description ?script ?args)
                 (announce_stage ?description)
                 (pipeline_sbcl ?sbcl)
                 (pipeline_root ?root)
                 (process_run ?sbcl ("--script" ?script . ?args) ((cwd ?root)) ?code)
                 (handle_stage_result ?description ?code))

             (<- (handle_stage_result ?description 0) !)
             (<- (handle_stage_result ?description ?code)
                 (format "Stage ~a failed with exit code ~a.~n" (?description ?code))
                 (halt 1))

             (<- (run_substeps nil) !)
             (<- (run_substeps ((?i ?d ?s ?a) . ?rest))
                 (run_stage ?d ?s ?a)
                 (run_substeps ?rest))

             (<- (run_stages nil) !)
             (<- (run_stages (?n . ?ns))
                 (setof (?i ?d ?s ?a) (substep ?n ?i ?d ?s ?a) ?subs)
                 (run_substeps ?subs)
                 (run_stages ?ns))

             (<- (run_pipeline)
                 (setof ?n (substep ?n ?i ?d ?s ?a) ?stages)
                 (run_stages ?stages))))
    (eval form)))
