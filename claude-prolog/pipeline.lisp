;;; pipeline.lisp -- a reusable "run an external pipeline" library for
;;; claude-prolog, factored out of sarcoma-setup.x (2026-09-14).
;;;
;;; The problem this solves recurs beyond one script: run a sequence of
;;; external processes, grouped into numbered stages with sub-steps
;;; within a stage, stopping with a clear error the moment one exits
;;; non-zero. sarcoma-setup.x's first Prolog draft still did the sequence/
;;; group PART in Prolog (SUBSTEP/5 facts, SETOF/3 grouping) but left the
;;; actual "run a process, check its exit code, report failure" part as
;;; hand-written Lisp -- exactly the part that isn't sarcoma-specific at
;;; all, and exactly the part most naturally expressed as Prolog clause
;;; dispatch (0 vs anything else) instead of a Lisp IF. This file moves
;;; that part here instead, so it's written once and reused, and so more
;;; of what a consuming script needs is already Prolog, not Lisp.
;;;
;;; Load this AFTER prolog-engine.lisp. A consuming script then needs
;;; only:
;;;   1. (setf *pipeline-root* ...) / (setf *pipeline-sbcl* ...) --
;;;      two lines, since nothing in Lisp can introspect "which directory
;;;      is the SCRIPT THAT LOADED ME in" from inside a library file --
;;;      *LOAD-TRUENAME* only reflects whichever file is being loaded at
;;;      the moment it's read, so the consuming script must capture its
;;;      own truename itself, once, right at its own top level.
;;;   2. SUBSTEP/5 facts: (substep StageNumber PositionInStage
;;;      Description ScriptPath ArgList) -- the pipeline's actual
;;;      content, and the one part that's genuinely specific to each
;;;      script, so it stays in the script, not here.
;;;   3. One call: (?- (run-pipeline)).
;;; Everything else -- grouping by stage, ordering within a stage,
;;; launching each external process, deciding success from failure, and
;;; reporting a failure clearly -- is this library, and all of the
;;; DECISION-MAKING in it (as opposed to the unavoidably-Lisp mechanism of
;;; actually starting an OS process) is Prolog.

(defun getenv-or (name default)
  "The one genuinely irreducible piece of environment-variable handling:
   SB-EXT:POSIX-GETENV isn't a *LISP-EVAL-FUNCTIONS* primitive and
   shouldn't become one (arbitrary Lisp special-form access has no
   business being callable from Prolog source generally) -- so it's a
   named, registered, single-purpose callable instead."
  (or (sb-ext:posix-getenv name) default))
(register-callable 'getenv-or)

(defparameter *pipeline-root* nil
  "Directory external stage scripts run in and are resolved relative to.
   A consuming script MUST set this (e.g. to its own *LOAD-TRUENAME*'s
   directory) before calling RUN-PIPELINE; NIL here is a deliberately
   loud failure (RUN-PROCESS-RAW errors) rather than a silent fallback to
   whatever the OS's own current directory happens to be.")

(defparameter *pipeline-sbcl*
  (getenv-or "SBCL" (namestring sb-ext:*runtime-pathname*))
  "The SBCL binary stage scripts are launched with. Defaults to this
   process's own binary, but -- matching the old sarcoma-setup.x's own
   documented SBCL override -- an SBCL environment variable set at
   pipeline.lisp load time wins first. A consuming script can still
   (setf *pipeline-sbcl* ...) afterward for a non-environment-variable
   override.")

(defun announce-stage (description)
  "Purely presentational -- the ==> banner a human watching the pipeline
   run sees before each stage starts."
  (format t "~%==> ~A~%" description)
  (finish-output)
  t)
(register-callable 'announce-stage)

(defun run-process-raw (script args)
  "Launch SCRIPT (relative to *PIPELINE-ROOT*) via *PIPELINE-SBCL* with
   ARGS, wait for it, and return its exit code as a plain integer --
   mechanism only. Whether that code means success or failure, and what
   to do about it, is RUN-STAGE's job below, in Prolog, not this
   function's."
  (unless *pipeline-root*
    (error "pipeline.lisp: *PIPELINE-ROOT* is unset -- the consuming script must (setf *pipeline-root* ...) before calling RUN-PIPELINE"))
  (let* ((process (sb-ext:run-program
                    *pipeline-sbcl* (append (list "--script" script) args)
                    :search t :directory *pipeline-root*
                    :input t :output t :error t :wait t)))
    (sb-ext:process-exit-code process)))
(register-callable 'run-process-raw)

(defun fail-stage (description code)
  "Exactly the old inline (ERROR ...) call, now named and shared."
  (error "Stage ~A failed with exit code ~S." description code))
(register-callable 'fail-stage)

;; --- from here down, every decision is Prolog: which clause matches IS
;;     the "if this stage succeeded, keep going; if not, report it and
;;     stop" logic, via ordinary first-argument clause selection on the
;;     exit code (0, or anything else) instead of a Lisp IF. ---

(<- (run-stage ?description ?script ?args)
    (lisp-eval t (announce-stage ?description))
    (lisp-eval ?code (run-process-raw ?script ?args))
    (handle-stage-result ?description ?code))

(<- (handle-stage-result ?description 0) !)
(<- (handle-stage-result ?description ?code)
    (lisp-eval t (fail-stage ?description ?code)))

(<- (run-substeps nil) !)
(<- (run-substeps ((?i ?d ?s ?a) . ?rest))
    (run-stage ?d ?s ?a)
    (run-substeps ?rest))

(<- (run-stages nil) !)
(<- (run-stages (?n . ?ns))
    (setof (?i ?d ?s ?a) (substep ?n ?i ?d ?s ?a) ?subs)
    (run-substeps ?subs)
    (run-stages ?ns))

(<- (run-pipeline)
    (setof ?n (substep ?n ?i ?d ?s ?a) ?stages)
    (run-stages ?stages))
