#!/usr/bin/env -S sbcl --script
;;;; Complete sarcoma pipeline -- Edinburgh-notation counterpart to
;;;; sarcoma-setup.x (2026-09-14). Identical behavior, identical stage
;;;; order, identical env-var overrides -- the only thing that changed is
;;;; that the ENV-VALUE/SUBSTEP facts, which were '(<- ...)' Lisp forms in
;;;; sarcoma-setup.x, now live in sarcoma-setup.pl, written in ordinary
;;;; Prolog textbook notation and loaded here with a single
;;;; (consult "sarcoma-setup.pl") -- see that file's own header for the
;;;; facts themselves and two small translation notes, and sarcoma-setup.x's
;;;; header for why the pipeline is stated as data (SUBSTEP/5 facts) at all.
;;;;
;;;; WHAT STAYS LISP, AND WHY: the shebang and the three `load`s below have
;;;; no Prolog content to port -- they're what makes Prolog (and, now,
;;;; Edinburgh notation) available in the first place. *PIPELINE-ROOT* is
;;;; ordinary path setup, same as before. The final (?- (run-pipeline)) also
;;;; STAYS bracket syntax rather than becoming '?-run-pipeline;':
;;;; RUN-PIPELINE is zero-arity, and the new '?-pred(...);' embedded-query
;;;; read-macro (edinburgh-read-macro.lisp) only fires for an identifier
;;;; sitting tight against a following '(' that has at least one argument
;;;; inside -- Edinburgh's own grammar rejects foo() for a 0-arity goal for
;;;; the identical reason (see edinburgh-reader.lisp's READ-ARGLIST error
;;;; message). A zero-arg goal simply has no natural spelling in either new
;;;; syntax, so the existing bracket form is the right tool here, exactly as
;;;; it always was -- not a workaround, just the one shape neither new
;;;; syntax was ever meant to cover.
;;;;
;;;; Overrides: SAR_EPOCHS (200), SAR_LR (0.002d0), SBCL. (SAR_FORCE_BASE_MAP
;;;; is read by the individual stage scripts themselves, not by this
;;;; orchestrator, so it's unaffected by this port and isn't mentioned here.)

(let* ((root (make-pathname :name nil :type nil :defaults *load-truename*))
       (*default-pathname-defaults* root))
  (load (merge-pathnames "claude-prolog/prolog-engine.lisp" root))
  (load (merge-pathnames "claude-prolog/edinburgh-reader.lisp" root))
  (load (merge-pathnames "claude-prolog/pipeline.lisp" root)))

(setf *pipeline-root* (make-pathname :name nil :type nil :defaults *load-truename*))

(consult (merge-pathnames "sarcoma-setup.pl" *pipeline-root*))

(?- (run-pipeline))
(format t "~%Done. Open: ~A~%"
        (merge-pathnames "output/cl-sarcoma-awrs-preferences.html" *pipeline-root*))
(sb-ext:exit)
