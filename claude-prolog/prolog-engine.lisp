(in-package :cl-user)

;; ============================================================================
;; claude-prolog engine, v6: everything from v2-v5 (trail-based destructive
;; binding, first-argument clause indexing, a standard-Prolog anonymous
;; variable, and the cut correctness fix), PLUS a clause COMPILER: each
;; Prolog-defined clause is now compiled, once, at ADD-CLAUSE time, into a
;; specialized native Lisp closure that performs its own head unification
;; and builds its own fresh body directly -- see "Compiling clauses" below
;; (read this one first, it's the new part).
;;
;; v1 (preserved as ~/csand/patrice-prolog) represented bindings as an
;; immutable alist threaded through every call -- a design straight out of
;; Boizumault's "The Implementation of Prolog". It is correct and reasonably
;; close to that book's presentation, but it has two performance problems:
;;
;;   1. Every dereference is a linear scan of that alist. For any predicate
;;      that is NOT perfectly tail-recursive with an empty choice-point
;;      stack at every step (i.e. most real Prolog code -- naive reverse
;;      being the textbook example), the alist never gets trimmed, so
;;      per-step cost grows with how deep into the computation you already
;;      are. Measured: nrev on a 160-element list took 18.8s in v1 versus
;;      SWI-Prolog's 0.0004s for the same call -- not a constant-factor
;;      gap, a different complexity class.
;;   2. clause-candidates fully renamed (copy-and-rename) BOTH the head and
;;      body of every clause of a predicate, for every call, before even
;;      checking whether the head unifies.
;;
;; v2 fixes both by giving each logic variable a mutable cell (a PVAR
;; struct) and a global TRAIL recording which cells got bound, so that
;; backtracking undoes bindings in O(1) each instead of discarding an alist
;; tail. Clause trial is lazy: only the head is renamed+unified before
;; deciding whether to bother renaming the body, and later clauses of a
;; predicate aren't even attempted until backtracking actually reaches them.
;;
;; Everything visible from OUTSIDE this file -- the <- macro, ?-/?-all,
;; the goal vocabulary (unify, lisp-eval, is, !, the comparison operators),
;; clear-database, *trace-prolog*, *occurs-check*, callable/register-callable
;; -- is unchanged, so every existing .lisp file in this project (the four
;; original test files, 5sum.lisp, 99/p01-p10.lisp, the bench/ scripts)
;; loads and runs against this file with no changes.
;;
;; v3 adds first-argument indexing (see CANDIDATE-CLAUSES below): v2 always
;; tried every clause of a predicate, in declaration order, even the ones
;; whose first argument obviously couldn't unify with the call. v3 files
;; each clause, as it's added, by the shape/value of its head's first
;; argument, so a call with a BOUND first argument only pays for
;; head-matching on the clauses that could actually match -- provably safe,
;; never changes which clauses succeed or their relative order.
;;
;; v4 gives the bare symbol _ real standard-Prolog anonymous-variable
;; semantics (see ANONYMOUS-VAR-P): every occurrence of _ is now a
;; DIFFERENT, unrelated variable, even within one clause head or query.
;; ?_ (with the question mark) still works exactly as it always did -- an
;; ordinary named variable -- but there's no longer any reason to write it
;; that way.
;;
;; v5 fixes a CORRECTNESS BUG in cut, inherited unchanged from
;; ~/csand/patrice-prolog (it predates this project entirely): the choice-
;; point truncation on ! kept the newest DEPTH choice points instead of the
;; oldest DEPTH -- backwards. Fixed by tracking each choice point's own
;; DEPTH directly (O(1)) and truncating with NTHCDR in the right direction.
;; See NOTES.md's v5 section for the full writeup and worked example.
;;
;; v6 compiles clauses instead of interpreting them. There are two kinds of
;; predicates here: PRIMITIVE ones (:cut, unify, lisp-eval, is, the
;; comparison operators) are already direct Lisp calls, dispatched by
;; BUILTIN-STEP -- nothing to compile, they're as fast as they'll get.
;; PROLOG-DEFINED ones (anything added via <-) were, through v5, matched by
;; a fully generic two-step interpretation on EVERY attempt: (1) INSTANTIATE
;; walked the clause's head AND body source, replacing every ?xxx symbol
;; with a fresh pvar via a freshly-allocated EQ hash table (so repeated
;; occurrences share one pvar) -- this fully rebuilds the clause's ENTIRE
;; term structure, unconditionally, even for clauses whose head obviously
;; won't match; then (2) generic UNIFY* walked the (now fully-built)
;; instantiated head against the call, cons cell by cons cell, re-deriving
;; at runtime facts about the clause's shape (is this position a variable?
;; a literal? a sub-list?) that were already fully known back when the
;; clause was first asserted.
;;
;; v6's COMPILE-CLAUSE (see "Compiling clauses" below) does this analysis
;; ONCE -- lazily, the first time a clause is actually offered as a match
;; candidate (see CLAUSE-MATCHER!), not at ADD-CLAUSE time; a clause
;; asserted but never tried never pays the compile cost at all, which
;; matters a lot for a large sparsely-queried fact database -- and emits
;; actual Lisp source implementing exactly this one clause's head match
;; and body construction, which is then handed to SBCL's own compiler
;; (COMPILE NIL ...) to become a real native closure. The generated
;; closure: (a) never builds the clause's head as a term at all -- it
;; matches the call's actual runtime structure directly, argument by
;; argument, calling BIND-VAR only where the clause is statically known
;; to introduce a fresh variable and full UNIFY* only where a variable is
;; statically known to repeat; (b) needs no per-attempt
;; hash table -- each of the clause's distinct named variables gets exactly
;; one lexical Lisp variable, allocated once via a LET at the top of the
;; closure, so sharing between repeated occurrences (and between head and
;; body) falls out of ordinary lexical scoping for free; (c) builds the
;; fresh body directly via nested CONS/MAKE-PVAR forms with ! already
;; compiled to (:CUT cut-depth), instead of INSTANTIATE's generic tree-walk
;; followed by a second REWRITE-CUTS pass. TRY-CLAUSES calls this compiled
;; matcher instead of INSTANTIATE+UNIFY*; everything else (indexing, the
;; trail, backtracking, cut execution itself in BUILTIN-STEP) is unchanged.
;; QUERIES are still instantiated the old, generic way (via INSTANTIATE) --
;; a query is only ever "run" once, so there's nothing to amortize a
;; compile against; compiling is specifically a win for CLAUSES, which get
;; matched against potentially many different calls over a program's life.
;; ============================================================================

(defparameter *database* (make-hash-table :test 'equal))
(defparameter *var-counter* 0)
(defparameter *trace-prolog* nil)
(defparameter *occurs-check* nil)

;; ---------------------------------------------------------------------------
;; Logic variables: mutable cells, not renamed symbols.
;; ---------------------------------------------------------------------------

(defconstant +unbound+ '+unbound+)

(defstruct (pvar (:constructor make-pvar (&key name))
                  (:print-function print-pvar))
  (value +unbound+)
  name
  (id (incf *var-counter*)))

(defun print-pvar (v stream depth)
  (declare (ignore depth))
  (format stream "_~A~D" (or (pvar-name v) "G") (pvar-id v)))

(defun variable-p (x)
  "True of a RUNTIME variable (an instantiated pvar cell). See
   raw-var-symbol-p for the SYNTACTIC check on clause/query source."
  (pvar-p x))

(defun anonymous-var-p (x)
  "True for the standard-Prolog anonymous variable, written as the bare
   symbol _ (no question mark -- there's nothing to name). Unlike every
   other variable, EVERY occurrence of _ denotes a DIFFERENT, unrelated
   variable, even within one clause head or one query -- so it's excluded
   from INSTANTIATE's usual same-symbol-same-pvar table (each occurrence
   gets its own fresh pvar), from QUERY-VARS, and (v6) from COLLECT-CLAUSE-
   VARS / gets its own fresh MAKE-PVAR wherever COMPILE-FRESH-TERM emits it,
   rather than a shared lexical variable."
  (and (symbolp x) (string= (symbol-name x) "_")))

(defun raw-var-symbol-p (x)
  "True if X, as written in clause or query SOURCE, is a symbol denoting a
   variable -- a named variable (starts with ?), or the anonymous variable
   (the bare symbol _; see ANONYMOUS-VAR-P, which needs a separate check
   since _ must NOT go through the same-symbol-same-pvar table below).
   This is used by INSTANTIATE (turning source into a term with real
   pvars), QUERY-VARS, INDEX-KEY, and (v6) COLLECT-CLAUSE-VARS/COMPILE-
   HEAD-MATCH/COMPILE-FRESH-TERM."
  (or (anonymous-var-p x)
      (and (symbolp x)
           (> (length (symbol-name x)) 0)
           (char= (char (symbol-name x) 0) #\?))))

;; ---------------------------------------------------------------------------
;; Trail: records which pvars got bound, so backtracking can undo them.
;; ---------------------------------------------------------------------------

(defparameter *trail* (make-array 4096 :adjustable t :fill-pointer 0))

(declaim (inline trail-mark trail-push maybe-clear-trail))

(defun trail-mark () (fill-pointer *trail*))

(defun trail-push (cell) (vector-push-extend cell *trail*))

(defun undo-to (mark)
  (loop while (> (fill-pointer *trail*) mark)
        do (setf (pvar-value (vector-pop *trail*)) +unbound+)))

(defun maybe-clear-trail (choices)
  "Nothing can backtrack past this point if there are no live choice
   points, so the trail (which exists only to support backtracking) can
   simply be forgotten -- not undone, just forgotten; the bindings it
   would have undone are now permanent, which is correct precisely
   because nothing remains that could ever ask to undo them."
  (when (null choices) (setf (fill-pointer *trail*) 0)))

;; ---------------------------------------------------------------------------
;; Dereference, unification, occurs-check, grounding.
;;
;; (Moved ahead of the clause database in v6, since COMPILE-CLAUSE -- used
;; by ADD-CLAUSE, just below -- calls PDEREF/BIND-VAR/UNIFY* directly.)
;; ---------------------------------------------------------------------------

(defun pderef (term)
  (loop while (and (pvar-p term) (not (eq (pvar-value term) +unbound+)))
        do (setf term (pvar-value term)))
  term)

(defun bind-var (var value)
  "Bind an unbound pvar VAR to VALUE, trailing it for backtracking.
   Returns T, or NIL if *occurs-check* is on and VALUE contains VAR."
  (if (and *occurs-check* (occurs-p var value))
      nil
      (progn (setf (pvar-value var) value) (trail-push var) t)))

(defun occurs-p (var term)
  (let ((term (pderef term)))
    (cond
      ((eq var term) t)
      ((consp term) (or (occurs-p var (car term)) (occurs-p var (cdr term))))
      (t nil))))

(defun unify* (a b)
  "Destructive unification. Returns T/NIL. On failure, any partial binds
   already made are left on the trail -- safe, because every caller that
   matters (TRY-CLAUSES, via a compiled clause matcher or otherwise)
   always undoes back to a pre-attempt mark on failure, and BUILTIN-STEP's
   callers (SOLVE-FROM) always backtrack immediately on a failed builtin
   goal, which also undoes past this point."
  (let ((a (pderef a)) (b (pderef b)))
    (cond
      ((equal a b) t)
      ((and (pvar-p a) (pvar-p b)) (bind-var b a))
      ((pvar-p a) (bind-var a b))
      ((pvar-p b) (bind-var b a))
      ((and (consp a) (consp b))
       (and (unify* (car a) (car b)) (unify* (cdr a) (cdr b))))
      (t nil))))

(defun ground (term)
  "Fully dereference TERM, recursively. An unbound variable prints as
   itself (via print-pvar) rather than as a raw source symbol."
  (let ((term (pderef term)))
    (cond
      ((pvar-p term) term)
      ((consp term) (cons (ground (car term)) (ground (cdr term))))
      (t term))))

;; ---------------------------------------------------------------------------
;; Compiling clauses (v6).
;;
;; COMPILE-CLAUSE turns one clause's raw HEAD/BODY source (exactly what's
;; passed to ADD-CLAUSE) into a native Lisp closure of two arguments,
;; CALL-ARGS (the actual call's arguments -- (cdr call), functor already
;; guaranteed to match by the predicate-key hash bucket this clause lives
;; in) and CUT-DEPTH (passed straight through from TRY-CLAUSES, exactly as
;; it always was): (funcall matcher call-args cut-depth) => (values
;; matched-p fresh-body). On a match, FRESH-BODY is this clause's body with
;; every variable freshly instantiated and every ! already rewritten to
;; (:cut cut-depth) -- ready to splice in front of the remaining goals,
;; exactly what INSTANTIATE+REWRITE-CUTS used to build together, but
;; constructed by generated code with no runtime tree-walk over the clause
;; source and no per-attempt EQ hash table.
;;
;; The key insight making this correct without any RUNTIME bookkeeping:
;; whether a given occurrence of a named variable in the HEAD should
;; directly BIND-VAR (it's provably the first thing to ever touch that
;; variable, so it's certainly still unbound) or must fall back to generic
;; UNIFY* (something upstream may already have bound it) is a function of
;; the clause's static left-to-right, depth-first argument order alone --
;; COMPILE-HEAD-MATCH decides it once, at compile time, with an ordinary
;; Lisp hash table (SEEN) that exists only while generating code, and bakes
;; the decision into which Lisp form it emits. See its docstring for the
;; exact rule, and why occurrences INSIDE a freshly-built substructure
;; (COMPILE-FRESH-TERM, used when the call's own argument at that position
;; is itself still unbound) do NOT count as "touched" for this purpose.
;; ---------------------------------------------------------------------------

(defun collect-clause-vars (head body)
  "The distinct NAMED variables (RAW-VAR-SYMBOL-P, excluding the anonymous
   _ -- see ANONYMOUS-VAR-P) appearing anywhere in HEAD or BODY, each of
   which gets exactly one pre-allocated pvar, shared by every occurrence
   (head or body alike) in COMPILE-CLAUSE's generated closure. Order is
   only for readability of generated code; correctness doesn't depend on
   it, since every use is a plain lexical variable reference."
  (let (vars)
    (labels ((walk (term)
               (cond
                 ((anonymous-var-p term) nil)
                 ((raw-var-symbol-p term) (pushnew term vars :test #'eq))
                 ((consp term) (walk (car term)) (walk (cdr term))))))
      (walk head)
      (dolist (goal body) (walk goal)))
    (nreverse vars)))

(defun compile-fresh-term (term var-alist)
  "A Lisp FORM that, when evaluated inside a COMPILE-CLAUSE closure (where
   every distinct named variable of VAR-ALIST is already bound to its
   shared lexical pvar -- possibly still unbound at runtime, possibly
   already bound by earlier processing within the SAME clause attempt;
   either way, referencing the cell itself is correct, since PDEREF
   resolves it whenever it's actually inspected later), builds a fresh
   copy of TERM: the anonymous variable _ becomes a brand-new pvar every
   time this form runs; a named variable becomes a direct reference to its
   shared lexical cell; a cons recurses via CONS on both car and cdr, so
   dotted-pair patterns like (?x . ?xs) build a genuine dotted pair and
   proper lists fall out of that automatically (exactly like INSTANTIATE's
   own (cons (instantiate (car term) ...) (instantiate (cdr term) ...)));
   anything else is a quoted literal, self-evaluating either way."
  (cond
    ((anonymous-var-p term) `(make-pvar :name '_))
    ((raw-var-symbol-p term) (cdr (assoc term var-alist :test #'eq)))
    ((consp term)
     `(cons ,(compile-fresh-term (car term) var-alist)
            ,(compile-fresh-term (cdr term) var-alist)))
    (t `',term)))

(defun compile-head-match (pattern call-form seen var-alist)
  "A Lisp FORM, evaluating to T/NIL, that matches CALL-FORM (a Lisp
   expression yielding the actual call-time argument at this head
   position) against PATTERN (raw clause-head source at this position),
   with side effects (BIND-VAR/UNIFY* calls) exactly where UNIFY* itself
   would have had them. SEEN is a compile-time-only EQ hash table (exists
   purely while generating code for THIS clause -- nothing to do with any
   runtime state) recording which named variables have already been
   DIRECTLY matched by a previous call to this function within the same
   clause; the rule:
     - _ always matches, no code needed at all (nothing downstream can
       ever reference it, so there is nothing to compute OR bind -- not
       even PDEREF'ing CALL-FORM, since _ imposes no constraint);
     - a named variable NOT YET in SEEN: this is, provably, the first
       thing in the whole clause to touch this variable's pvar, so it
       must currently be unbound -- emit an unconditional (BIND-VAR
       lexical-cell (PDEREF call-form)), and mark it seen. (An occurrence
       that appeared EARLIER only inside another position's COMPILE-
       FRESH-TERM -- i.e. embedded, unbound, into a larger structure that
       got bound to something -- does NOT mark it seen: embedding a cell
       into a structure doesn't touch the cell itself. This mirrors
       INSTANTIATE+UNIFY*'s own behavior exactly: INSTANTIATE creates
       every clause pvar UNBOUND up front, sharing cells by symbol name,
       and only UNIFY*'s left-to-right depth-first walk over the
       instantiated head ever actually binds one -- so a variable
       embedded inside an earlier argument's substructure is, at that
       point, still just as unbound as if it had never been mentioned.)
     - a named variable ALREADY in SEEN: something upstream in this same
       clause attempt may have bound it already (or it may still be
       unbound, if that upstream touch turned out to be inside a fresh-
       term embedding rather than a direct bind) -- either way, only
       generic (UNIFY* lexical-cell call-form) is safe;
     - a cons pattern (A . D): CALL-FORM's actual runtime shape isn't
       known until then, so PDEREF it once (via a LET, so nested car/cdr
       accesses below don't re-derive it) and branch three ways: if it's
       an unbound pvar, there is nothing to structurally compare against
       yet, so build a fresh mirror of the WHOLE pattern (COMPILE-FRESH-
       TERM) and BIND-VAR the call's cell to it in one step (this is the
       only place COMPILE-FRESH-TERM is invoked from head-matching, and
       it recurses over the FULL pattern, so occurrences inside it are
       exactly the \"embedded, not yet touched\" case described above);
       if it's a real cons, recurse structurally into car/cdr, exactly
       matching UNIFY*'s own (AND (UNIFY* (CAR A)(CAR B)) (UNIFY* (CDR A)
       (CDR B))); otherwise (a bound atom that isn't a cons) this
       position simply cannot match a cons-shaped pattern, fail;
     - anything else (a literal) delegates to plain (UNIFY* 'pattern
       call-form) -- UNIFY* already handles a literal against a bound
       atom, a bound cons (fails), or an unbound pvar (binds it)
       correctly and cheaply; no reason to hand-roll it."
  (cond
    ((anonymous-var-p pattern) t)
    ((raw-var-symbol-p pattern)
     (let ((lex (cdr (assoc pattern var-alist :test #'eq))))
       (if (gethash pattern seen)
           `(unify* ,lex ,call-form)
           (progn (setf (gethash pattern seen) t)
                  `(bind-var ,lex (pderef ,call-form))))))
    ((consp pattern)
     (let ((c (gensym "C")))
       `(let ((,c (pderef ,call-form)))
          (cond
            ((pvar-p ,c) (bind-var ,c ,(compile-fresh-term pattern var-alist)))
            ((consp ,c) (and ,(compile-head-match (car pattern) `(car ,c) seen var-alist)
                              ,(compile-head-match (cdr pattern) `(cdr ,c) seen var-alist)))
            (t nil)))))
    (t `(unify* ',pattern ,call-form))))

(defun compile-clause (head body)
  "Compile HEAD/BODY (a clause's raw source, exactly as ADD-CLAUSE
   receives it) into the native closure described in this section's
   banner comment. Muffles the SBCL style-warnings an ordinary COMPILE
   would print for a generated lambda with a variable used in only one
   branch of a COND (harmless -- every lexical variable IS referenced
   somewhere in the generated form, just not necessarily on every runtime
   path) -- otherwise loading a file that asserts many clauses would print
   one warning block per clause."
  (let* ((vars (collect-clause-vars head body))
         (var-alist (mapcar (lambda (v) (cons v (gensym (symbol-name v)))) vars))
         (head-args (if (consp head) (cdr head) nil))
         (seen (make-hash-table :test 'eq))
         (call-args-sym (gensym "CALL-ARGS"))
         (cut-depth-sym (gensym "CUT-DEPTH"))
         (match-forms
           (loop for pat in head-args
                 for i from 0
                 collect (compile-head-match pat `(nth ,i ,call-args-sym) seen var-alist)))
         (body-forms
           (mapcar (lambda (goal)
                     (if (eq goal '!)
                         `(list :cut ,cut-depth-sym)
                         (compile-fresh-term goal var-alist)))
                   body))
         (lambda-form
           `(lambda (,call-args-sym ,cut-depth-sym)
              (declare (ignorable ,call-args-sym ,cut-depth-sym))
              (let ,(mapcar (lambda (pair) `(,(cdr pair) (make-pvar :name ',(car pair))))
                             var-alist)
                (declare (ignorable ,@(mapcar #'cdr var-alist)))
                (if (and ,@(or match-forms '(t)))
                    (values t (list ,@body-forms))
                    (values nil nil))))))
    (handler-bind ((warning #'muffle-warning))
      (compile nil lambda-form))))

;; ---------------------------------------------------------------------------
;; Clause database, with first-argument indexing.
;;
;; Each predicate's clauses are still kept in one flat, ordered list (PRED-
;; ENTRY-ALL) -- that's what's used whenever indexing can't help (arity 0,
;; or a call whose first argument is itself unbound). But every clause is
;; ALSO filed, at ADD-CLAUSE time, into one of:
;;   - PRED-ENTRY-VAR-CLAUSES, if its head's first argument is a raw
;;     variable (?x) -- such a clause unifies with ANY call, so it must
;;     always be a candidate, for any call, indexing or not;
;;   - PRED-ENTRY-KEYED, an EQUAL hash table from "shape key" to the
;;     ordered clauses with that key -- :CONS for any clause whose first
;;     argument is a compound/list term, or the argument's own literal
;;     value (compared with EQUAL, the same equality UNIFY* already uses
;;     for its non-variable fast path) for anything else.
;;
;; At lookup time (CANDIDATE-CLAUSES), a call with a BOUND first argument
;; only needs to try PRED-ENTRY-VAR-CLAUSES plus whichever ONE keyed bucket
;; matches its own shape/value -- every other clause is guaranteed to fail
;; on its first argument alone. This never changes which clauses succeed,
;; or their relative order -- it only skips paying for a (now-compiled)
;; head-match attempt on clauses that were always going to fail anyway.
;; Each clause carries a global SEQ number so the var-clauses and the one
;; matching keyed bucket -- two lists each already in declaration order --
;; can be merged back into a single list in original declaration order
;; (MERGE-BY-SEQ).
;; ---------------------------------------------------------------------------

(defparameter *clause-seq* 0)

;; MATCHER starts NIL -- see CLAUSE-MATCHER! just below for why COMPILE-
;; CLAUSE is no longer called eagerly, at ADD-CLAUSE time.
(defstruct clause head body seq matcher)

(defun clause-matcher! (clause)
  "This clause's compiled matcher (see COMPILE-CLAUSE above), compiled
   LAZILY on first need and cached in the clause's MATCHER slot from then
   on -- so a clause that's asserted but never actually offered as a
   match candidate never pays the compile cost at all, and one that's
   tried many times pays it exactly once, same as before.

   This matters in practice: compiling calls SBCL's real compiler, which
   costs real (sub-millisecond, but non-trivial) time per clause -- fine
   when amortized over many calls to a handful of clauses (the common
   case: a recursive helper predicate like MYAPP or a queens-solver
   clause, called thousands of times over 2-4 clauses), but NOT fine for
   a large static fact database asserted once and queried sparsely --
   e.g. 16,000 ground facts loaded via ADD-CLAUSE, where first-argument
   indexing (v3) already means a typical bound-key lookup only ever
   candidates a handful of those clauses. Eagerly compiling all 16,000 up
   front, whether or not they're ever looked up, measured ~5.3s just to
   load them (vs. ~0.35s pre-compiler) -- a real, unnecessary regression
   for exactly the large-fact-database scaling use case v3's indexing was
   built for. Compiling lazily instead makes ADD-CLAUSE itself cheap
   again (an O(1) hash/list insert, as it always was) and spends the
   compile cost only on clauses actually visited while solving -- see
   NOTES.md's v6 section for the measured numbers."
  (or (clause-matcher clause)
      (setf (clause-matcher clause) (compile-clause (clause-head clause) (clause-body clause)))))

(defstruct pred-entry
  (all nil)
  (var-clauses nil)
  (keyed (make-hash-table :test 'equal)))

;; A choice point remembers what's needed to LAZILY retry the remaining
;; clauses of one predicate call: the call itself, the goals waiting after
;; it, which clauses are still untried, the cut-depth those clauses' bodies
;; should be rewritten against, the trail mark to undo back to before
;; retrying, the outer choice points beyond this one, and this choice
;; point's own DEPTH -- see CHOICES-DEPTH just below for why.
(defstruct choice call rest remaining-clauses cut-depth trail-mark choices depth)

(declaim (inline choices-depth))
(defun choices-depth (choices)
  "The number of live choice points in CHOICES -- O(1), by reading the
   depth stored on the top (newest) one, rather than (LENGTH CHOICES),
   which would be O(depth) and was recomputed on EVERY single predicate
   call in SOLVE-FROM (not just ones that use cut). Each choice's DEPTH
   is set once, at creation, in TRY-CLAUSES."
  (if choices (choice-depth (car choices)) 0))

(defun clear-database ()
  (clrhash *database*)
  (setf (fill-pointer *trail*) 0)
  (setf *clause-seq* 0))

(defun predicate-key (term)
  (if (consp term)
      (cons (car term) (length (cdr term)))
      (cons term 0)))

(defun head-first-arg (head)
  "Returns (values has-arg-p arg), where HAS-ARG-P is NIL for an arity-0
   head (a bare symbol, or a one-element list -- just the functor, no
   arguments)."
  (if (and (consp head) (cdr head))
      (values t (second head))
      (values nil nil)))

(defun index-key (arg)
  "The shape key for indexing purposes: :VAR for a variable -- a raw
   source symbol like ?x (RAW-VAR-SYMBOL-P) when ARG comes from clause
   head source, or a still-unbound runtime cell (PVAR-P) when ARG comes
   from a call's (PDEREF'd) argument -- :CONS for any compound/list-
   shaped term, or the term's own literal value otherwise."
  (cond
    ((or (raw-var-symbol-p arg) (pvar-p arg)) :var)
    ((consp arg) :cons)
    (t arg)))

(defun add-clause (head body)
  (let* ((key (predicate-key head))
         (entry (or (gethash key *database*)
                    (setf (gethash key *database*) (make-pred-entry))))
         (clause (make-clause :head head :body body :seq (incf *clause-seq*))))
    (setf (pred-entry-all entry) (append (pred-entry-all entry) (list clause)))
    (multiple-value-bind (has-arg arg) (head-first-arg head)
      (let ((k (if has-arg (index-key arg) :var)))
        (if (eq k :var)
            (setf (pred-entry-var-clauses entry)
                  (append (pred-entry-var-clauses entry) (list clause)))
            (setf (gethash k (pred-entry-keyed entry))
                  (append (gethash k (pred-entry-keyed entry)) (list clause))))))
    head))

(defmacro <- (head &body body)
  `(add-clause ',head ',body))

(defun merge-by-seq (a b)
  "Stably merge clause lists A and B -- each already sorted by CLAUSE-SEQ
   -- into one list sorted by CLAUSE-SEQ, i.e. original declaration order."
  (cond
    ((null a) b)
    ((null b) a)
    ((< (clause-seq (car a)) (clause-seq (car b)))
     (cons (car a) (merge-by-seq (cdr a) b)))
    (t (cons (car b) (merge-by-seq a (cdr b))))))

(defun candidate-clauses (goal)
  "The ordered list of GOAL's predicate's clauses that could possibly
   unify with GOAL. Falls back to the full clause list, unfiltered, when
   the predicate has arity 0 or GOAL's own first argument is unbound --
   in both cases indexing has nothing to rule out."
  (let ((entry (gethash (predicate-key goal) *database*)))
    (cond
      ((null entry) nil)
      ((not (and (consp goal) (cdr goal))) (pred-entry-all entry))
      (t (let ((call-key (index-key (pderef (second goal)))))
           (if (eq call-key :var)
               (pred-entry-all entry)
               (merge-by-seq (pred-entry-var-clauses entry)
                              (gethash call-key (pred-entry-keyed entry)))))))))

;; ---------------------------------------------------------------------------
;; Turning QUERY source (?xxx symbols) into a term with fresh pvars.
;;
;; Clauses no longer go through this -- see "Compiling clauses" above --
;; but a query is only ever run once, so compiling one would cost more
;; than it could ever save; INSTANTIATE remains exactly what it was for
;; that one remaining use (and REWRITE-CUTS is gone: a query itself is
;; never allowed to contain a bare !, so there's nothing to rewrite; a
;; clause's ! is now compiled directly to (:cut cut-depth) by COMPILE-
;; CLAUSE's BODY-FORMS).
;; ---------------------------------------------------------------------------

(defun instantiate (term table)
  "Walk raw source TERM, replacing each ?xxx symbol with a fresh pvar --
   the SAME pvar for repeated occurrences of the same symbol within this
   one call (tracked via TABLE, an eq hash table) -- EXCEPT the anonymous
   variable _, which always gets a brand-new pvar, never shared via TABLE,
   even for the second, third, ... occurrence in this same call."
  (cond
    ((anonymous-var-p term) (make-pvar :name term))
    ((raw-var-symbol-p term)
     (or (gethash term table)
         (setf (gethash term table) (make-pvar :name term))))
    ((consp term)
     (cons (instantiate (car term) table) (instantiate (cdr term) table)))
    (t term)))

;; ---------------------------------------------------------------------------
;; The arithmetic/Lisp escape hatch (lisp-eval / is), unchanged in spirit.
;; ---------------------------------------------------------------------------

(defparameter *lisp-eval-functions*
  '(+ - * / 1+ 1- = /= < > <= >= min max abs mod rem floor ceiling round
    truncate zerop plusp minusp not))

(defun register-callable (function-name)
  (unless (and (symbolp function-name) (fboundp function-name))
    (error "Not a callable Lisp function: ~S" function-name))
  (pushnew function-name *lisp-eval-functions* :test #'eq)
  function-name)

(defmacro callable (spec)
  "Allow a Lisp function to be called from lisp-eval.

The argument names in a list spec are documentation only:
  (callable sqrt)
  (callable (sqrt x))
  (callable (sqrt x y))
all register SQRT."
  (let ((function-name (if (consp spec) (car spec) spec)))
    `(register-callable ',function-name)))

(defun eval-prolog-form (form)
  "Fixed 2026-09-14 (see NOTES.md's rough-edges section for the long
   version): FORM is either a source EXPRESSION to interpret (an
   application of some *LISP-EVAL-FUNCTIONS* member to sub-expressions,
   or a literal) or a VARIABLE whose current value should just be
   returned as-is, however that value is shaped -- those are different
   jobs, and the previous version conflated them by re-dispatching on
   PDEREF's result regardless of which one it started as. WAS-VAR
   captures which job this call is (a variable reference, however many
   PDEREF hops it takes to resolve) *before* PDEREF replaces FORM with
   its value, so a variable bound to a cons -- a real list, most commonly
   -- comes back as that list, terminal data, instead of PDEREF's result
   being mistaken for a fresh expression and having ITS car probed as if
   it might be a function name."
  (let ((was-var (pvar-p form)))
    (let ((form (pderef form)))
      (cond
        ((pvar-p form) (error "Unbound variable in lisp-eval: ~S" form))
        (was-var form)
        ((atom form) form)
        ((eq (car form) 'quote) (second form))
        ((member (car form) *lisp-eval-functions*)
         (apply (symbol-function (car form)) (mapcar #'eval-prolog-form (cdr form))))
        (t (error "Function not allowed in lisp-eval: ~S" (car form)))))))

;; ---------------------------------------------------------------------------
;; Built-in goals.
;; ---------------------------------------------------------------------------

(defun builtin-p (goal)
  (and (consp goal)
       (member (car goal) '(:cut unify lisp-eval is = /= < > <= >=
                             findall bagof setof call))))

(defun builtin-step (goal rest choices)
  "Returns (values new-goals new-choices ok)."
  (case (and (consp goal) (car goal))
    (:cut
     ;; DEPTH is how many choice points existed when the CURRENT clause
     ;; was entered (captured, since v6, directly in COMPILE-CLAUSE's
     ;; generated (LIST :CUT cut-depth) -- previously by REWRITE-CUTS at
     ;; the same logical moment) -- ! must discard every choice point
     ;; created SINCE then (this clause's own "try the next clause of
     ;; this predicate" choice, plus any pushed by body goals before
     ;; reaching !) while preserving every OLDER one, from ancestor
     ;; calls, untouched. CHOICES is newest-first (a new choice point is
     ;; CONSed onto the front -- see TRY-CLAUSES), so "everything since
     ;; clause entry" is a PREFIX of CHOICES, and what must survive the
     ;; cut is the SUFFIX of the oldest DEPTH entries:
     ;; (NTHCDR (- current-depth DEPTH) CHOICES). (An earlier version of
     ;; this engine -- inherited all the way back from patrice-prolog --
     ;; used (SUBSEQ CHOICES 0 DEPTH) here, which keeps the newest DEPTH
     ;; entries instead: backwards. See NOTES.md's v5 section.)
     (let ((depth (second goal)))
       (values rest (nthcdr (- (choices-depth choices) depth) choices) t)))
    (unify
     (values rest choices (unify* (second goal) (third goal))))
    (lisp-eval
     (values rest choices (unify* (second goal) (eval-prolog-form (third goal)))))
    (is
     (values rest choices (unify* (second goal) (eval-prolog-form (third goal)))))
    ((= /= < > <= >=)
     ;; Fixed 2026-09-14, motivated by the Edinburgh reader: was (MAPCAR
     ;; #'GROUND ...), which only fully dereferences pvars but never
     ;; evaluates -- fine as long as every argument ever handed to these
     ;; six was already a plain grounded number (the only way anyone
     ;; could use them before: via LISP-EVAL, e.g. (lisp-eval t (= ?n
     ;; 1)), which evaluates its OWN argument before ever reaching this
     ;; case). Once source can write a comparison directly as a goal
     ;; (X < Y + 1), its operands can be compound terms like (+ ?y 1)
     ;; that need evaluating, not just dereferencing -- GROUND would hand
     ;; Lisp's < a literal list and crash with a raw Lisp type error
     ;; instead of computing anything. EVAL-PROLOG-FORM is a strict
     ;; superset of GROUND's behavior here: for an already-grounded ATOM
     ;; (a plain number -- everything every existing caller ever passed),
     ;; the two are identical (see EVAL-PROLOG-FORM's (ATOM FORM) case),
     ;; so nothing that worked before changes; only the previously-
     ;; crashing compound-argument case is now handled at all.
     (values rest choices (apply (symbol-function (car goal)) (mapcar #'eval-prolog-form (cdr goal)))))
    (findall
     (values rest choices (unify* (fourth goal) (findall-collect (second goal) (third goal)))))
    (bagof
     (let ((results (findall-collect (second goal) (third goal))))
       (values rest choices (and results (unify* (fourth goal) results)))))
    (setof
     (let ((results (sort (remove-duplicates (findall-collect (second goal) (third goal))
                                              :test #'equal :from-end t)
                           #'term-lessp)))
       (values rest choices (and results (unify* (fourth goal) results)))))
    (call
     (values (cons (build-call-goal (second goal) (cddr goal)) rest) choices t))
    (otherwise (values nil choices nil))))

;; ---------------------------------------------------------------------------
;; FINDALL/BAGOF/SETOF/CALL -- added 2026-09-14, motivated by wanting to
;; express a small declarative pipeline (facts describing ordered stages/
;; substeps, grouped and sorted for execution) instead of hand-rolled list
;; recursion. All four are ordinary GENERAL-INTERPRETER builtins, dispatched
;; in BUILTIN-STEP exactly like UNIFY/LISP-EVAL -- none of this touches
;; MODE-COMPILER.LISP; a moded clause body still can't call them (same as it
;; can't call any non-moded predicate), which is intentional: this is search/
;; enumeration machinery, the opposite of what the mode compiler exists to
;; bypass.
;;
;; CURRENT LIMITATION: the Goal argument to FINDALL/BAGOF/SETOF must be a
;; single goal term, not a (G1, G2, ...) conjunction -- there is no ','/2 in
;; this engine (clause bodies are already a flat goal LIST at the source
;; level, so conjunction has never needed its own functor). Every use so far
;; (grouping/filtering over a fact database) only ever needed one goal; if a
;; real conjunctive need shows up, wrapping goal-list splicing into this is a
;; small, well-understood follow-up, not attempted here.
;; ---------------------------------------------------------------------------

(defun findall-collect (template goal)
  "Run GOAL to exhaustion via backtracking (its own private search --
   choice points it creates never escape this function), collecting a
   fully-grounded copy of TEMPLATE for every solution, in solution order.
   Every binding GOAL's search made is undone before returning, exactly
   like Prolog's real FINDALL: only the collected snapshot survives, via
   whatever the caller unifies the returned list with."
  (let ((mark (trail-mark)) (results nil))
    (multiple-value-bind (choices ok) (solve-from (list goal) nil)
      (loop while ok
            do (push (ground template) results)
               (multiple-value-bind (bok bgoals bchoices) (backtrack choices)
                 (if bok
                     (multiple-value-bind (c2 ok2) (solve-from bgoals bchoices)
                       (setf choices c2 ok ok2))
                     (setf ok nil)))))
    (undo-to mark)
    (nreverse results)))

(defun term-rank (x)
  "Coarse type ordering for TERM-LESSP, only as fine as this engine's own
   term vocabulary needs: numbers, then strings, then symbols, then conses,
   then anything else -- good enough for sorting SETOF's own kind of small
   mixed tuples, not a claim of full ISO standard-order-of-terms coverage."
  (cond ((numberp x) 0) ((stringp x) 1) ((symbolp x) 2) ((consp x) 3) (t 4)))

(defun term-lessp (a b)
  "A total order over grounded terms, used only to SORT -- SETOF's -- own
   collected results. Numbers compare numerically, strings/symbols
   lexicographically, conses element-wise (car, then cdr, exactly like
   comparing two lists lexicographically); anything else falls back to
   TERM-RANK."
  (cond
    ((and (numberp a) (numberp b)) (< a b))
    ((and (stringp a) (stringp b)) (string< a b))
    ((and (symbolp a) (symbolp b)) (string< (symbol-name a) (symbol-name b)))
    ((and (consp a) (consp b))
     (cond ((term-lessp (car a) (car b)) t)
           ((term-lessp (car b) (car a)) nil)
           (t (term-lessp (cdr a) (cdr b)))))
    ((and (null a) (consp b)) t)
    ((and (consp a) (null b)) nil)
    (t (< (term-rank a) (term-rank b)))))

(defun build-call-goal (goal-term extra-args)
  "CALL/N's own construction step: GOAL-TERM (already PDEREF'd to its
   current value) plus EXTRA-ARGS appended becomes the actual goal to
   solve next. Unlike FINDALL/BAGOF/SETOF, CALL does NOT run an isolated
   sub-search -- it hands the constructed goal back to the ordinary
   resolution loop (see its BUILTIN-STEP case: the new goal is simply
   consed onto REST), so its choice points backtrack exactly like any
   goal written directly in source would."
  (let ((g (pderef goal-term)))
    (cond
      ((null extra-args) g)
      ((consp g) (cons (car g) (append (cdr g) extra-args)))
      ((symbolp g) (cons g extra-args))
      (t (error "prolog-engine: CALL/~D's goal argument ~S is neither a predicate symbol nor a compound term"
                (1+ (length extra-args)) g)))))

;; ---------------------------------------------------------------------------
;; Clause trial and backtracking.
;; ---------------------------------------------------------------------------

(defun try-clauses (call clauses rest cut-depth outer-choices)
  "Try CLAUSES against CALL in order, using each clause's own compiled
   matcher (see \"Compiling clauses\" above) instead of a generic
   INSTANTIATE+UNIFY* pass. On the first whose head matches, return
   (values t new-goals new-choices): new-goals splices the matcher's
   freshly-built body before REST, and new-choices pushes a choice point
   for whatever clauses are still untried (if any) on top of OUTER-
   CHOICES. Each failed head-match is fully undone before the next clause
   is tried -- clauses never see one another's partial bindings; this is
   unchanged from v2-v5, since the compiled matcher still just calls
   BIND-VAR/UNIFY*, which still just trail bindings for UNDO-TO to unwind.
   Returns (values nil) if none of CLAUSES match CALL."
  (loop for remaining on clauses
        for clause = (car remaining)
        do (let ((mark (trail-mark)))
             (multiple-value-bind (matched new-body)
                 (funcall (clause-matcher! clause) (cdr call) cut-depth)
               (if matched
                   (let* ((new-goals (append new-body rest))
                          (new-choices
                            (if (cdr remaining)
                                (cons (make-choice :call call :rest rest
                                                    :remaining-clauses (cdr remaining)
                                                    :cut-depth cut-depth
                                                    :trail-mark mark
                                                    :choices outer-choices
                                                    :depth (1+ (choices-depth outer-choices)))
                                      outer-choices)
                                outer-choices)))
                     (return (values t new-goals new-choices)))
                   (undo-to mark))))
        finally (return (values nil nil nil))))

(defun backtrack (choices)
  "Pop and resume choice points until one of them actually produces a new
   path, or none are left. Returns (values ok new-goals new-choices)."
  (loop
    (unless choices (return (values nil nil nil)))
    (let ((choice (pop choices)))
      (undo-to (choice-trail-mark choice))
      (multiple-value-bind (found new-goals new-choices)
          (try-clauses (choice-call choice) (choice-remaining-clauses choice)
                       (choice-rest choice) (choice-cut-depth choice)
                       (choice-choices choice))
        (if found
            (return (values t new-goals new-choices))
            (setf choices (choice-choices choice)))))))

;; ---------------------------------------------------------------------------
;; The resolution loop.
;; ---------------------------------------------------------------------------

(defun solve-from (initial-goals initial-choices)
  "Returns (values choices ok). On success, whatever pvars the caller
   cares about (its protected-vars) can just be GROUND directly -- there
   is no bindings object to thread through."
  (loop with goals = initial-goals
        with choices = initial-choices
        do
           (maybe-clear-trail choices)
           (cond
             ((null goals) (return (values choices t)))
             (t
              (let ((goal (car goals)) (rest (cdr goals)))
                (when *trace-prolog* (format t "~&~S~%" (ground goal)))
                (multiple-value-bind (found new-goals new-choices)
                    (if (builtin-p goal)
                        (multiple-value-bind (ng nc ok) (builtin-step goal rest choices)
                          (values ok ng nc))
                        (let ((clauses (candidate-clauses goal))
                              (cut-depth (choices-depth choices)))
                          (try-clauses goal clauses rest cut-depth choices)))
                  (if found
                      (setf goals new-goals choices new-choices)
                      (multiple-value-bind (bok bgoals bchoices) (backtrack choices)
                        (if bok
                            (setf goals bgoals choices bchoices)
                            (return (values nil nil)))))))))))

;; ---------------------------------------------------------------------------
;; Query entry points.
;; ---------------------------------------------------------------------------

(defun query-goals (query)
  (if (and (consp query) (consp (car query)))
      query
      (list query)))

(defun query-vars (term)
  "Raw source NAMED-variable names (in first-occurrence order), from a
   quoted query as written -- e.g. the ?xxx symbols in
   '(count-up3 0 10000 ?result). Excludes the anonymous variable _ (see
   ANONYMOUS-VAR-P): standard Prolog never reports a binding for it, and
   since every _ is its own independent variable there's no single
   binding to report in the first place."
  (let (vars)
    (labels ((walk (x)
               (cond
                 ((anonymous-var-p x) nil)
                 ((raw-var-symbol-p x) (pushnew x vars :test #'eq))
                 ((consp x) (walk (car x)) (walk (cdr x))))))
      (walk term))
    (nreverse vars)))

(defun instantiate-query (raw-query)
  "Returns (values instantiated-query protected-vars), where
   protected-vars is the list of pvars corresponding to raw-query's own
   variables, in first-occurrence order."
  (let* ((raw-vars (query-vars raw-query))
         (table (make-hash-table :test 'eq))
         (instantiated (instantiate raw-query table)))
    (values instantiated (mapcar (lambda (v) (gethash v table)) raw-vars))))

(defun solve-one (raw-query)
  "Returns (values protected-vars choices ok)."
  (multiple-value-bind (query protected-vars) (instantiate-query raw-query)
    (multiple-value-bind (choices ok) (solve-from (query-goals query) nil)
      (values protected-vars choices ok))))

(defun solve-next (choices protected-vars)
  "Returns (values protected-vars choices ok)."
  (multiple-value-bind (bok bgoals bchoices) (backtrack choices)
    (if bok
        (multiple-value-bind (choices2 ok2) (solve-from bgoals bchoices)
          (values protected-vars choices2 ok2))
        (values protected-vars nil nil))))

(defun print-solution (protected-vars)
  (if protected-vars
      (dolist (v protected-vars)
        (format t "~&~A = ~S" (pvar-name v) (ground v)))
      (format t "~&yes"))
  (terpri))

(defun run-query (raw-query)
  (multiple-value-bind (protected-vars choices ok) (solve-one raw-query)
    (declare (ignore choices))
    (if ok
        (progn (print-solution protected-vars) (mapcar #'ground protected-vars))
        (progn (format t "~&no~%") nil))))

(defun run-all-query (raw-query)
  (loop with answer-count = 0
        with choices = nil
        with protected-vars = nil
        for first = t then nil
        do
           (multiple-value-bind (pv c ok)
               (if first
                   (solve-one raw-query)
                   (solve-next choices protected-vars))
             (setf protected-vars pv)
             (unless ok
               (when (zerop answer-count) (format t "~&no~%"))
               (return answer-count))
             (incf answer-count)
             (format t "~&Answer ~D:" answer-count)
             (print-solution protected-vars)
             (setf choices c))))

(defun macro-query-form (forms)
  (cond
    ((null forms) (error "Query requires at least one goal"))
    ((null (cdr forms)) (car forms))
    (t forms)))

(defmacro ?- (&body query)
  `(run-query ',(macro-query-form query)))

(defmacro ?-all (&body query)
  `(run-all-query ',(macro-query-form query)))
