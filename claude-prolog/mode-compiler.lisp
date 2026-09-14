;; ============================================================================
;; mode-compiler.lisp -- prototype, load AFTER prolog-engine.lisp (v6).
;;
;; Eduardo's idea: a DETERMINISTIC predicate with a MODE declaration (which
;; argument positions are inputs, bound at call time, and which are outputs,
;; produced by the call) can compile directly to a native Lisp function that
;; takes the input values as plain Lisp arguments and returns the output
;; values via (VALUES ...) -- no pvars, no trail, no choice points, no
;; unification at all. This is a strictly stronger optimization than v6's
;; per-clause compiler (which still allocates pvars and calls BIND-VAR/
;; UNIFY* for generality): a moded predicate's whole call is just ordinary
;; Lisp function application, and a self-recursive moded predicate (like
;; COUNT-UP3) becomes an ordinary tail-recursive Lisp function that SBCL can
;; tail-call-optimize exactly as if a human had hand-written it that way.
;;
;; DECLARING A MODE: (mode (pred-name m1 m2 ... mn)), one m per argument
;; position of PRED-NAME/N, each + (bound on call, an input) or - (produced
;; by the call, an output). Declare it AFTER asserting all of the
;; predicate's clauses via <- (exactly as usual) -- MODE reads them out of
;; the ordinary clause database and compiles them; nothing about <- itself
;; changes, and the predicate remains fully usable the ordinary
;; (interpreted/v6-compiled) way too if you still query it via ?-/?-all.
;; Compiling registers a native Lisp function named MODED-<PRED>-<ARITY>
;; (see DET-FN-NAME), callable directly.
;;
;; SCOPE OF THIS PROTOTYPE (restrictions, all checked at compile time with a
;; clear error -- lifting any of these is future work, not attempted here):
;;   - An INPUT (+) position's pattern may be a bare variable, the
;;     anonymous _, a literal, OR (since 2026-09-14) a compound (cons)
;;     pattern, matched by recursively destructuring the already-bound
;;     value with CAR/CDR, guarded by CONSP at each level -- e.g.
;;     (+x . +xs) as a + position matches any non-empty list, binding X to
;;     its head and XS to its tail. See COMPILE-DET-CLAUSE's docstring.
;;   - An OUTPUT (-) position's pattern may likewise (since 2026-09-14) be
;;     a compound pattern, built by recursively CONSing its parts -- e.g.
;;     (-x . -z) as a - position builds a fresh cons of X (which usually
;;     already has a value from elsewhere in the same head, as in APPEND
;;     below) onto Z (usually produced by the clause's own trailing moded
;;     call). See COMPILE-DET-CLAUSE's docstring for exactly how a
;;     compound output's not-yet-bound leaves get resolved, and why doing
;;     this costs the literal-tail-call TCO guarantee that a flat output
;;     shape (COUNT-UP3, RELAY, etc) still gets.
;;   - Every predicate CALLED from a moded clause's body must itself be
;;     moded (no falling back to the general engine for an un-moded
;;     sub-goal).
;;   - A call to another moded predicate may appear ONLY as the very LAST
;;     goal in a clause body. Its own outputs no longer need to line up
;;     1:1, in order, with the clause's own outputs (that's now just the
;;     condition for the fast literal-tail-call path -- see COMPILE-DET-
;;     CLAUSE); what's still required is that the call be textually last,
;;     and that every one of the clause's own still-unresolved outputs be
;;     produced by SOME output of that call. A moded call anywhere else in
;;     a body (its result feeding further computation, or more goals
;;     following it) is not supported by this prototype.
;;   - Body goals otherwise supported: !  (no-op: clause selection here is
;;     just COND, there's no choice-point machinery to cut), LISP-EVAL/IS
;;     (either a T-guard, or defining a not-yet-bound variable, or an
;;     equality check against an already-known value), UNIFY (defining a
;;     not-yet-bound variable from the other side, or an equality check),
;;     and the direct comparison builtins (=, /=, <, >, <=, >=).
;; ============================================================================

(defparameter *det-modes* (make-hash-table :test 'equal))
(defparameter *det-functions* (make-hash-table :test 'equal))

(defun det-fn-name (pred arity)
  (intern (format nil "MODED-~:@(~A~)-~D" pred arity)))

(defun translate-det-expr (expr var-alist)
  "Translate a raw source EXPR (a variable, a literal, or a LISP-EVAL/IS-
   style arithmetic subexpression built from *LISP-EVAL-FUNCTIONS*) into a
   Lisp form referencing this clause's already-established lexical
   bindings (VAR-ALIST: raw var symbol -> Lisp expression, almost always
   just another lexical variable's name)."
  (cond
    ((anonymous-var-p expr)
     (error "mode-compiler: _ cannot appear inside an expression"))
    ((raw-var-symbol-p expr)
     (let ((e (assoc expr var-alist :test #'eq)))
       (unless e (error "mode-compiler: ~S used before being bound" expr))
       (cdr e)))
    ((consp expr)
     (if (member (car expr) *lisp-eval-functions*)
         `(,(car expr) ,@(mapcar (lambda (a) (translate-det-expr a var-alist)) (cdr expr)))
         (error "mode-compiler: ~S is not in *lisp-eval-functions*, can't compile" (car expr))))
    (t expr)))

(defparameter *det-list-accessor-watchlist*
  '(car cdr caar cadr cdar cddr caaar caadr cadar caddr
    cdaar cdadr cddar cdddr first rest second third fourth nth elt)
  "Functions that, applied to a variable inside LISP-EVAL/IS, usually mean
   'this variable is bound to a list, let me pick it apart'. Until
   2026-09-14 this idiom also had a real correctness bug (EVAL-PROLOG-FORM
   mishandling a dereferenced variable that turned out to be a cons, see
   NOTES.md) that made it silently break under the general interpreted
   engine (?-/?-all) even though it compiled and ran fine directly; that
   bug is now fixed. What's left is purely a style point: since the
   compound head-pattern extension (also 2026-09-14), this idiom is
   essentially never necessary for LIST destructuring specifically --
   (pred (?h . ?t) ...) in the clause head does the same job more
   idiomatically -- so COMPILE-DET-CLAUSE still warns (not errors: the
   clause is valid and correct either way now) whenever it sees one of
   these applied to a bare variable in a clause body, as a style nudge
   rather than a correctness one.")

(defun scan-for-risky-list-access (expr pred arity)
  "Walk a raw (pre-translation) LISP-EVAL/IS expression for a call to a
   *DET-LIST-ACCESSOR-WATCHLIST* function on a bare Prolog variable, e.g.
   (car ?lst) -- and warn if found. See *DET-LIST-ACCESSOR-WATCHLIST*'s
   docstring for why this is worth flagging rather than leaving silent."
  (when (consp expr)
    (when (and (member (car expr) *det-list-accessor-watchlist*)
               (some #'raw-var-symbol-p (cdr expr)))
      (warn "mode-compiler: ~S/~D uses (~S ~{~S~^ ~}) inside LISP-EVAL/IS in a ~
clause body. This is correct (EVAL-PROLOG-FORM's list-dereference bug was fixed ~
2026-09-14) but destructuring a list this way in the BODY is no longer the more ~
idiomatic style now that compound head patterns exist -- prefer ~
(~A (?h . ?t) ...) in the clause HEAD instead of (lisp-eval ?h (~S ?lst)) in the body."
            pred arity (car expr) (cdr expr) pred (car expr)))
    (dolist (sub (cdr expr))
      (scan-for-risky-list-access sub pred arity))))

(defun template-holes (template)
  "All :HOLE leaf names anywhere in TEMPLATE (see BUILD-OUT-TEMPLATE
   inside COMPILE-DET-CLAUSE), left to right; a name can repeat if it
   occurs more than once in the template."
  (ecase (first template)
    (:resolved nil)
    (:hole (list (second template)))
    (:cons (append (template-holes (second template))
                    (template-holes (third template))))))

(defun render-det-template (template)
  "Turn a fully-resolved output TEMPLATE (see BUILD-OUT-TEMPLATE inside
   COMPILE-DET-CLAUSE) into the Lisp expression that computes it. Every
   :HOLE must already have been patched to :RESOLVED by the time this
   runs -- an unpatched :HOLE reaching here is this file's own bug, not
   a user error (user-facing unresolved-output errors are raised
   earlier, in COMPILE-DET-CLAUSE, naming the actual output position
   that has no producer)."
  (ecase (first template)
    (:resolved (second template))
    (:cons `(cons ,(render-det-template (second template))
                  ,(render-det-template (third template))))
    (:hole (error "mode-compiler: internal error -- unresolved output hole ~S reached codegen" (second template)))))

(defun compile-det-clause (head body mode params)
  "Compile one clause of a moded predicate into (values test-form
   body-form) -- one COND clause in the generated function (see COMPILE-
   DET-PREDICATE). PARAMS is the function's parameter list, one lexical
   per + position, in order.

   Supports COMPOUND (cons) patterns at both + and - positions (added
   2026-09-14 for APPEND -- see this file's banner comment): a +
   position's pattern is matched by recursively destructuring the
   already-bound input value with CAR/CDR, guarded by CONSP at each
   level (MATCH-IN-PATTERN below). A - position's pattern is built as an
   output TEMPLATE -- a tree of the same cons shape whose leaves are
   either :RESOLVED (a Lisp expression already known by the time the
   head is processed: a repeated variable's existing binding, or a
   quoted literal) or :HOLE (a not-yet-bound variable name, BUILD-OUT-
   TEMPLATE below). After the clause's body is compiled, every :HOLE is
   re-checked against the (now possibly larger) VAR-ALIST -- a body
   LISP-EVAL/IS/UNIFY step may have bound it in the meantime -- and
   whatever's STILL a hole at that point must be produced by the
   clause's own trailing moded call (RESOLVE-TEMPLATE below); anything
   left unresolved after that is a compile-time error naming the
   offending output, not a silently wrong function.

   Two ways the trailing call can supply those holes, chosen
   automatically:
   - FAST PATH: every output position is a single, never-otherwise-bound
     hole, and the sequence of their names matches the trailing call's
     own output names, in order -- exactly the ORIGINAL (pre-compound-
     pattern) behavior. Compiles to a literal Lisp tail call, which
     SBCL tail-call-optimizes (see COUNT-UP3/RELAY's O(1)-stack tests).
   - GENERAL PATH: anything else with a trailing moded call (a compound
     output template, or hole names not lining up 1:1 in order). The
     call is wrapped in MULTIPLE-VALUE-BIND instead, and the real output
     structure is reconstructed from its results. Still correct, but no
     longer a tail call -- APPEND-shaped predicates (cons the current
     element onto whatever the recursive call produces) inherently need
     the callee's result BEFORE they can finish building their own, so
     this costs the same one-stack-frame-per-recursive-step that the
     equivalent hand-written non-tail-recursive Lisp/Prolog definition
     would cost -- it's not a missed optimization, it's what the shape
     of the computation actually requires."
  (let ((var-alist nil)
        (guards nil)
        (out-order nil)
        (param-i 0))
    (labels
        ((match-in-pattern (pattern value-expr)
           "+ side: PATTERN is already fully bound; VALUE-EXPR is a Lisp
            expression for its current value (a parameter, or a CAR/CDR
            chain into one). Mutates GUARDS/VAR-ALIST."
           (cond
             ((anonymous-var-p pattern) nil)
             ((raw-var-symbol-p pattern)
              (let ((existing (assoc pattern var-alist :test #'eq)))
                (if existing
                    (push `(equal ,(cdr existing) ,value-expr) guards)
                    (push (cons pattern value-expr) var-alist))))
             ((consp pattern)
              (push `(consp ,value-expr) guards)
              (match-in-pattern (car pattern) `(car ,value-expr))
              (match-in-pattern (cdr pattern) `(cdr ,value-expr)))
             (t (push `(equal ',pattern ,value-expr) guards))))
         (build-out-template (pattern)
           "- side: build PATTERN's output template -- see this
            function's docstring for the :RESOLVED/:HOLE/:CONS shapes.
            Reads (does not mutate) VAR-ALIST, so this must run AFTER
            every + position has already been matched (COMPILE-DET-
            CLAUSE processes + positions in a first pass for exactly
            this reason -- see below -- regardless of each position's
            own left-to-right order in the head)."
           (cond
             ((anonymous-var-p pattern)
              `(:hole ,(gensym "IGNORED-OUT")))
             ((raw-var-symbol-p pattern)
              (let ((existing (assoc pattern var-alist :test #'eq)))
                (if existing `(:resolved ,(cdr existing)) `(:hole ,pattern))))
             ((consp pattern)
              `(:cons ,(build-out-template (car pattern))
                      ,(build-out-template (cdr pattern))))
             (t `(:resolved ',pattern))))
         (resolve-template (template)
           "Re-check every :HOLE in TEMPLATE against VAR-ALIST as it
            stands AFTER body processing -- picks up anything a body
            LISP-EVAL/IS/UNIFY step bound in the meantime. Whatever's
            still a :HOLE afterward must come from the trailing moded
            call, or is an error -- see COMPILE-DET-CLAUSE's main body."
           (ecase (first template)
             (:resolved template)
             (:cons `(:cons ,(resolve-template (second template))
                            ,(resolve-template (third template))))
             (:hole (let ((e (assoc (second template) var-alist :test #'eq)))
                      (if e `(:resolved ,(cdr e)) template))))))
      ;; Pass 1: every + position, matching/destructuring against the
      ;; function's own parameters. Done for ALL + positions before ANY
      ;; - position is processed (regardless of their relative order in
      ;; the head) so BUILD-OUT-TEMPLATE always sees the complete input-
      ;; derived VAR-ALIST when it decides whether one of its variables
      ;; is already known (like APPEND's repeated X) or still a hole.
      (loop for arg in (cdr head)
            for m in mode
            do (unless (member m '(+ -))
                 (error "mode-compiler: mode entries must be + or - (got ~S)" m))
            when (eq m '+)
              do (let ((p (nth param-i params)))
                   (incf param-i)
                   (match-in-pattern arg p)))
      ;; Pass 2: every - position, building this clause's output
      ;; templates, in head-declaration order.
      (loop for arg in (cdr head)
            for m in mode
            when (eq m '-)
              do (push (build-out-template arg) out-order))
      (setf out-order (nreverse out-order))
      (let ((let-bindings nil) (tail-call-info nil) (goals body))
        (loop while goals
              for goal = (pop goals)
              do (cond
                   ((eq goal '!) nil)
                   ((and (consp goal) (member (car goal) '(lisp-eval is)))
                    (let* ((target (second goal)) (expr (third goal)))
                      (scan-for-risky-list-access expr (car head) (length (cdr head)))
                      (let ((val-form (translate-det-expr expr var-alist)))
                      (cond
                        ((eq target 't) (push val-form guards))
                        ((and (raw-var-symbol-p target) (not (anonymous-var-p target))
                              (not (assoc target var-alist :test #'eq)))
                         (let ((lex (gensym (symbol-name target))))
                           (push (cons target lex) var-alist)
                           (push (list lex val-form) let-bindings)))
                        (t (push `(equal ,(translate-det-expr target var-alist) ,val-form) guards))))))
                   ((and (consp goal) (eq (car goal) 'unify))
                    (let* ((a (second goal)) (b (third goal))
                           (a-new (and (raw-var-symbol-p a) (not (anonymous-var-p a))
                                       (not (assoc a var-alist :test #'eq))))
                           (b-new (and (raw-var-symbol-p b) (not (anonymous-var-p b))
                                       (not (assoc b var-alist :test #'eq)))))
                      (cond
                        (a-new (let ((lex (gensym (symbol-name a))))
                                 (push (cons a lex) var-alist)
                                 (push (list lex (translate-det-expr b var-alist)) let-bindings)))
                        (b-new (let ((lex (gensym (symbol-name b))))
                                 (push (cons b lex) var-alist)
                                 (push (list lex (translate-det-expr a var-alist)) let-bindings)))
                        (t (push `(equal ,(translate-det-expr a var-alist) ,(translate-det-expr b var-alist)) guards)))))
                   ((and (consp goal) (member (car goal) '(= /= < > <= >=)))
                    (push `(,(car goal) ,@(mapcar (lambda (a) (translate-det-expr a var-alist)) (cdr goal))) guards))
                   ((consp goal)
                    (let* ((pname (car goal)) (args (cdr goal)) (arity (length args))
                           (key (cons pname arity)) (cmode (gethash key *det-modes*)))
                      (unless cmode
                        (error "mode-compiler: ~S/~D called from a moded clause has no MODE declaration (~S)" pname arity head))
                      (unless (null goals)
                        (error "mode-compiler: moded call to ~S/~D must be the LAST goal in the clause body (~S)" pname arity head))
                      (let ((callee-name (gethash key *det-functions*))
                            (in-exprs nil) (out-names nil))
                        (loop for a in args for m in cmode
                              do (if (eq m '+)
                                     (push (translate-det-expr a var-alist) in-exprs)
                                     (push a out-names)))
                        (setf in-exprs (nreverse in-exprs) out-names (nreverse out-names))
                        (setf tail-call-info (list callee-name in-exprs out-names)))))
                   (t (error "mode-compiler: unsupported body goal ~S" goal))))
        ;; Resolve every output template against the now body-complete
        ;; VAR-ALIST (picks up anything a body step bound), then decide
        ;; how the trailing call (if any) supplies whatever's still
        ;; unresolved -- see this function's docstring for the two paths.
        (setf out-order (mapcar #'resolve-template out-order))
        (let* ((all-flat-holes-p (every (lambda (tpl) (eq (first tpl) :hole)) out-order))
               (flat-hole-names (and all-flat-holes-p (mapcar #'second out-order)))
               (test-form (if guards `(and ,@(nreverse guards)) 't)))
          (cond
            ;; FAST PATH.
            ((and tail-call-info all-flat-holes-p
                  (equal flat-hole-names (third tail-call-info)))
             (let ((call-form `(,(first tail-call-info) ,@(second tail-call-info))))
               (values test-form
                       (if let-bindings `(let* ,(nreverse let-bindings) ,call-form) call-form))))
            ;; GENERAL PATH: a trailing moded call whose results need
            ;; reshaping.
            (tail-call-info
             (destructuring-bind (callee-name in-exprs out-names) tail-call-info
               (let* ((remaining-holes (remove-duplicates
                                         (mapcan #'template-holes out-order) :test #'eq))
                      (missing (set-difference remaining-holes out-names :test #'eq)))
                 (when missing
                   (error "mode-compiler: output(s) ~S have no producer -- no body step binds them, and they don't match any output of the trailing call to ~S (~S)"
                          missing callee-name head))
                 (let* ((call-gensyms (mapcar (lambda (n) (declare (ignore n)) (gensym "OUT")) out-names))
                        (name->gensym (mapcar #'cons out-names call-gensyms))
                        (patched-out-order
                          (labels ((patch (tpl)
                                     (ecase (first tpl)
                                       (:resolved tpl)
                                       (:cons `(:cons ,(patch (second tpl)) ,(patch (third tpl))))
                                       (:hole (let ((g (cdr (assoc (second tpl) name->gensym :test #'eq))))
                                                (if g `(:resolved ,g) tpl))))))
                            (mapcar #'patch out-order)))
                        (unused-gensyms (mapcar (lambda (n) (cdr (assoc n name->gensym :test #'eq)))
                                                 (set-difference out-names remaining-holes :test #'eq)))
                        (return-exprs (mapcar #'render-det-template patched-out-order))
                        (mvb-form
                          `(multiple-value-bind (ok ,@call-gensyms) (,callee-name ,@in-exprs)
                             (declare (ignorable ,@unused-gensyms))
                             (if ok (values t ,@return-exprs) (values nil)))))
                   (values test-form
                           (if let-bindings `(let* ,(nreverse let-bindings) ,mvb-form) mvb-form))))))
            ;; No trailing moded call -- every output must already be
            ;; fully resolved from the head/body alone.
            (t
             (let ((unresolved (remove-duplicates (mapcan #'template-holes out-order) :test #'eq)))
               (when unresolved
                 (error "mode-compiler: output(s) ~S have no producer in this clause (~S)" unresolved head)))
             (values test-form
                     `(let* ,(nreverse let-bindings)
                        (values t ,@(mapcar #'render-det-template out-order)))))))))))

(defun compile-det-predicate (pred arity modes)
  "Compile PRED/ARITY (already asserted via <-, with MODES as its mode
   list) into one native Lisp function -- see this file's banner comment.
   Returns the generated function's name."
  (let* ((key (cons pred arity))
         (entry (gethash key *database*))
         (clauses (and entry (pred-entry-all entry))))
    (unless clauses
      (error "mode-compiler: no clauses found for ~S/~D -- assert them via <- before declaring MODE" pred arity))
    (unless (= (length modes) arity)
      (error "mode-compiler: MODE for ~S has ~D entries, but arity is ~D" pred (length modes) arity))
    (setf (gethash key *det-modes*) modes)
    (let* ((fn-name (det-fn-name pred arity))
           (n-in (count '+ modes))
           (params (loop repeat n-in collect (gensym "IN"))))
      ;; Registered BEFORE compiling the body, so a self-recursive call
      ;; inside this predicate's own clauses (see COUNT-UP3 below) resolves
      ;; to this same FN-NAME.
      (setf (gethash key *det-functions*) fn-name)
      (let* ((cond-clauses
               (mapcar (lambda (c)
                         (multiple-value-bind (test body)
                             (compile-det-clause (clause-head c) (clause-body c) modes params)
                           (list test body)))
                       clauses))
             (lambda-form
               `(lambda ,params
                  (declare (ignorable ,@params))
                  (cond ,@cond-clauses (t (values nil))))))
        ;; COMPILE takes a NAME plus a LAMBDA (not a full DEFUN form); a
        ;; self-recursive call inside LAMBDA-FORM refers to FN-NAME as an
        ;; ordinary function-call symbol, which resolves fine at runtime
        ;; once SYMBOL-FUNCTION is set below (SBCL only style-warns about
        ;; the forward reference at compile time, muffled same as
        ;; COMPILE-CLAUSE does in the main engine).
        (handler-bind ((warning #'muffle-warning))
          (setf (symbol-function fn-name) (compile nil lambda-form)))
        fn-name))))

(defmacro mode (spec)
  (let* ((pred (car spec)) (modes (cdr spec)) (arity (length modes)))
    `(compile-det-predicate ',pred ,arity ',modes)))

;; ============================================================================
;; Fortran-style inline mode syntax (2026-09-14, polarity fixed 2026-09-14)
;;
;; Eduardo: "we could act like Fortran: output variables would start with +,
;; input variables would start with -, and two way variables would be a
;; question mark. +x is output, -x is input and ?x is logic variable."
;;
;; This lets a clause head name its mode directly in its own variable names
;; -- (<- (count-up3 +n +stop -out) ...) -- instead of a separate (mode ...)
;; declaration after the fact. Scope, confirmed with Eduardo before writing
;; this:
;;   - Applies to HEAD ARGUMENTS ONLY. Body variables are unaffected and
;;     stay ordinary ?x syntax; the existing first-occurrence-binds/repeat-
;;     unifies inference for body variables is untouched.
;;   - If a clause head MIXES +/- annotated variables with a bare ?x
;;     variable, that's an error (not a silent fallback) -- annotate every
;;     variable position in a head, or none.
;;
;; ONE POLARITY, NOT TWO: Eduardo initially described +=output/-=input (the
;; Fortran convention above), which is the OPPOSITE of this file's existing
;; explicit MODE macro (+=input, -=output -- see its own banner comment,
;; inherited from Eduardo's original mode-declaration description:
;; "...put the output variables together at the end"). Having the two
;; mechanisms disagree about what + and - mean was flagged as a problem to
;; avoid, not a difference to document and live with -- so the inline
;; syntax below uses the SAME convention as MODE: +=input, -=output. Only
;; one polarity exists in this file now; there is nothing left to
;; translate between.
;;
;; The Lisp reader disambiguates the syntax for free: -5 and +5 read as
;; NUMBERS (not symbols), so a literal input/output like -5 or +3.0 in a
;; head position is never mistaken for an annotated variable -- MODED-VAR-P
;; below starts with a SYMBOLP check, which literal numbers simply fail.
;; ============================================================================

(defun moded-var-p (x)
  "True if X, as written in a clause HEAD, is a Fortran-style inline
   mode-annotated variable: a symbol (not a number -- see banner comment
   above) whose name starts with + or - and has at least one more
   character after the prefix, e.g. +X, -STOP, +OUT2."
  (and (symbolp x)
       (not (keywordp x))
       (let ((name (symbol-name x)))
         (and (> (length name) 1)
              (member (char name 0) '(#\+ #\-))))))

(defun moded-var-canonical (x)
  "Strip X's +/- prefix and return the canonical ?-spelled symbol that the
   rest of the engine (ordinary ADD-CLAUSE, v6's compiler, indexing, a
   repeated occurrence of the same variable elsewhere in the clause)
   understands -- e.g. +OUT -> ?OUT, -N -> ?N. Interned in X's own
   package so this works the same whether the clause is read in CL-USER
   or elsewhere."
  (intern (concatenate 'string "?" (subseq (symbol-name x) 1))
          (symbol-package x)))

(defun moded-var-direction (x)
  "X's mode direction, read straight off its prefix: + = input, - =
   output -- the same convention as the explicit MODE macro (see the
   banner comment above: there is only one polarity in this file)."
  (ecase (char (symbol-name x) 0)
    (#\+ '+)
    (#\- '-)))

(defun det-pattern-contains-moded-var-p (pattern)
  "True if PATTERN -- one clause-head ARGUMENT, possibly a nested cons
   pattern like (+X . +XS) -- contains a Fortran-style inline mode-
   annotated variable ANYWHERE in it, at its own top level or nested
   arbitrarily deep inside a compound (cons) pattern."
  (cond
    ((moded-var-p pattern) t)
    ((consp pattern)
     (or (det-pattern-contains-moded-var-p (car pattern))
         (det-pattern-contains-moded-var-p (cdr pattern))))
    (t nil)))

(defun strip-moded-pattern (pattern)
  "Recursively replace every Fortran-style inline mode-annotated
   variable anywhere in PATTERN -- top-level or nested inside a compound
   cons pattern -- with its canonical ?-form (MODED-VAR-CANONICAL),
   leaving everything else (plain ?-variables, _, literals, the cons
   structure itself) untouched."
  (cond
    ((moded-var-p pattern) (moded-var-canonical pattern))
    ((consp pattern)
     (cons (strip-moded-pattern (car pattern))
           (strip-moded-pattern (cdr pattern))))
    (t pattern)))

(defun strip-moded-head (head)
  "Parse clause HEAD = (PRED ARG1 ARG2 ...). If no ARG contains an
   inline +/- annotated variable anywhere in it (DET-PATTERN-CONTAINS-
   MODED-VAR-P, which looks inside compound/cons patterns too -- e.g.
   (+X . +XS)), return (values HEAD NIL) -- an ordinary clause,
   untouched.

   Otherwise every TOP-LEVEL argument that's a bare variable must be
   +/- annotated (a bare ?x logic variable mixed in at the top level is
   an error, per Eduardo's confirmed answer that a mixed head refuses
   inline compilation); non-variable top-level positions (a literal,
   the anonymous _, or a COMPOUND/cons pattern) may appear freely,
   annotated or not. A variable NESTED inside a compound pattern may be
   written with or without a +/- prefix either way -- COMPILE-DET-
   CLAUSE determines a nested variable's role (matched vs. constructed)
   from VAR-ALIST at compile time, not from its own decoration, so
   there's nothing to enforce there (see COMPILE-DET-CLAUSE's
   docstring); the mixing rule below only looks at each argument's own
   top-level spelling.

   On success, returns (values STRIPPED-HEAD MODES): STRIPPED-HEAD has
   every annotated variable, wherever it occurs, replaced by its
   canonical ?-form (so the clause, once stored, is indistinguishable
   from one written with ordinary ?-syntax throughout -- full backward
   compatibility with the general engine, v6's compiler, and indexing).
   MODES is one entry per TOP-LEVEL argument position, using the SAME
   +=input/-=output convention as the explicit MODE macro: + or - for a
   bare annotated variable, NIL for a literal, _, or COMPOUND position
   (a compound position's direction isn't determined by inline syntax
   alone -- same bucket as a literal position, needing an explicit MODE
   call to resolve -- see MERGE-DET-MODES)."
  (let* ((pred (car head)) (args (cdr head)))
    (if (notany #'det-pattern-contains-moded-var-p args)
        (values head nil)
        (let ((bad (find-if (lambda (a) (and (raw-var-symbol-p a)
                                              (not (anonymous-var-p a))
                                              (not (moded-var-p a))))
                             args)))
          (when bad
            (error "mode-compiler: clause head ~S mixes a Fortran-style +/- annotated variable with plain variable ~S -- annotate every top-level variable position in a head, or none" head bad))
          (let ((new-args nil) (modes nil))
            (dolist (a args)
              (cond
                ((consp a)
                 (push (strip-moded-pattern a) new-args)
                 (push nil modes))
                ((moded-var-p a)
                 (push (moded-var-canonical a) new-args)
                 (push (moded-var-direction a) modes))
                (t
                 (push a new-args)
                 (push nil modes))))
            (values (cons pred (nreverse new-args)) (nreverse modes)))))))

(defparameter *det-mode-progress* (make-hash-table :test 'equal)
  "PRED.ARITY -> the running per-argument-position mode list (+/-/nil,
   same convention as the explicit MODE macro) merged across every
   clause of that predicate asserted so far via the inline +/- syntax.
   NIL in a position means no clause has resolved that position's
   direction yet (it's always been a literal or _ there) -- see
   MERGE-DET-MODES and STRIP-MODED-HEAD.")

(defun merge-det-modes (key new-modes head)
  "Merge NEW-MODES (one freshly-asserted inline-annotated clause's
   per-position modes, possibly with NILs) into *DET-MODE-PROGRESS*'s
   running modes for KEY = (PRED . ARITY). A
   position resolves permanently the first time any clause gives it a
   non-NIL direction; two clauses giving OPPOSITE directions for the same
   position is a clear compile-time error, not silently resolved either
   way. Returns the merged list (STILL possibly containing NILs, if some
   position has only ever appeared as a literal/_ so far)."
  (let ((existing (gethash key *det-mode-progress*)))
    (if (null existing)
        (setf (gethash key *det-mode-progress*) (copy-list new-modes))
        (setf (gethash key *det-mode-progress*)
              (mapcar (lambda (old new)
                        (cond
                          ((and old new (not (eq old new)))
                           (error "mode-compiler: ~S/~D has clauses whose inline +/- annotations disagree about the direction of the same argument position -- one earlier clause resolved it one way, and clause ~S resolves it the other way" (car key) (cdr key) head))
                          (old old)
                          (t new)))
                      existing new-modes)))))

(defun register-moded-clause (head body inline-modes)
  "Called (at RUNTIME, from the redefined <- macro below) for a clause
   whose head used Fortran-style inline +/- annotation. HEAD is already
   stripped to canonical ?-form and BODY is the ordinary clause body --
   asserted via the ordinary ADD-CLAUSE, so this predicate remains fully
   usable via ?-/?-all and v6's clause compiler exactly like any other,
   whether or not it ends up with a compiled MODED-... function too.

   Then merges INLINE-MODES into *DET-MODE-PROGRESS* for this predicate,
   and -- once every argument position has a resolved (non-NIL) direction
   -- automatically (re)compiles MODED-<PRED>-<ARITY> via COMPILE-DET-
   PREDICATE. No explicit (mode ...) call needed for a predicate defined
   entirely with inline syntax; each new clause simply retriggers a fresh
   recompile against the full clause set so far, same as calling MODE
   again by hand would.

   Known limitation: if some argument position is a literal (or _) in
   EVERY clause of the predicate, its direction can never be inferred
   from inline syntax alone (a literal carries no +/- prefix to read),
   so that predicate never auto-compiles this way -- the explicit MODE
   macro remains available as a manual fallback (it works fine here too,
   since the stored clause is plain ?-syntax underneath)."
  (add-clause head body)
  (let* ((pred (car head)) (arity (length (cdr head))) (key (cons pred arity))
         (merged (merge-det-modes key inline-modes head)))
    (when (every (lambda (m) (member m '(+ -))) merged)
      (compile-det-predicate pred arity merged))))

;; Redefining <- (originally from prolog-engine.lisp) is intentional --
;; SBCL style-warns about it ("redefining ... in DEFMACRO"), muffled here
;; the same way COMPILE-CLAUSE/COMPILE-DET-PREDICATE muffle their own
;; forward-reference warnings elsewhere in this project.
(handler-bind ((warning #'muffle-warning))
  (defmacro <- (head &body body)
    "Shadows PROLOG-ENGINE.LISP's <- (see ADD-CLAUSE above). Detects
     Fortran-style inline +/- mode annotation in HEAD (STRIP-MODED-HEAD)
     at MACROEXPANSION time -- HEAD is a literal form here, never
     evaluated, so this costs nothing at runtime and doesn't disturb
     ordinary clauses at all: a clause with no inline annotation expands
     to exactly the same (ADD-CLAUSE ',head ',body) as the original macro,
     byte for byte."
    (multiple-value-bind (stripped-head inline-modes) (strip-moded-head head)
      (if inline-modes
          `(register-moded-clause ',stripped-head ',body ',inline-modes)
          `(add-clause ',stripped-head ',body)))))
