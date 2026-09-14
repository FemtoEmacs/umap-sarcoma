(load "prolog-engine.lisp")
(load "mode-compiler.lisp")

;; ============================================================================
;; 6sum.lisp -- does the mode-compiler prototype work with LISTS?
;;
;; Eduardo's recollection of how this went in his own past Prolog-in-Lisp
;; implementation: an INPUT list gets its structure read with CAR/CDR, an
;; OUTPUT list gets built with CONS. This file checks that against the
;; current mode-compiler.lisp -- it hadn't actually been exercised with
;; lists before, and it turned out to need real work, in two stages:
;;
;; 1. The CAR/CDR/CONS-IN-THE-BODY idiom Eduardo remembered -- an input
;;    argument is already fully bound by the time the clause body runs,
;;    so its structure can be read with ordinary Lisp CAR/CDR calls
;;    inside LISP-EVAL/IS, and a fresh output structure built the same
;;    way with CONS. This part needed no new compiler support: CAR/CDR/
;;    CONS aren't in *LISP-EVAL-FUNCTIONS* by default (prolog-
;;    engine.lisp ships with arithmetic only), but they're ordinary Lisp
;;    functions, so the existing (callable ...) macro (already part of
;;    prolog-engine.lisp, predating this whole mode-compiler project)
;;    registers them exactly like any other Lisp function -- and once
;;    registered, both the general interpreted engine's LISP-EVAL/IS and
;;    the mode-compiler's TRANSLATE-DET-EXPR can use them, since they
;;    share the same *LISP-EVAL-FUNCTIONS* table. LISTSUM and DOUBLED
;;    below use this idiom.
;;
;; 2. Real head-level COMPOUND (cons) patterns, e.g. (+x . +xs) -- what
;;    Eduardo actually asked for next, with APPEND as the test case. This
;;    WAS unsupported: a moded clause's head positions could only be a
;;    bare variable, _, or a literal, and a cons pattern in either a +
;;    or a - position was a flat compile-time error (see mode-tests.
;;    lisp's old "badcons" case, now repurposed as a positive test).
;;    Lifting that restriction is real new compiler work -- see mode-
;;    compiler.lisp's COMPILE-DET-CLAUSE docstring -- and it's what
;;    APPEND, further down, actually exercises.
;;
;; Along the way, cross-checking LISTSUM's moded result against the
;; general INTERPRETED engine (via a plain (?- ...) query using the same
;; CAR/CDR-in-LISP-EVAL idiom) surfaced a genuine, pre-existing rough
;; edge in prolog-engine.lisp's EVAL-PROLOG-FORM, unrelated to anything
;; in this file or in mode-compiler.lisp: it dereferences a variable and,
;; if the dereferenced VALUE is itself a cons -- which a bound LIST
;; always is -- tries to re-interpret that value as a further nested
;; expression to evaluate (checking whether ITS car is a registered
;; function) instead of returning it as a terminal data value. So
;; (lisp-eval ?h (car ?lst)) works fine when ?lst is a LOGIC VARIABLE
;; that's about to be dereferenced ONCE, but breaks the moment the thing
;; ?lst derefs to is itself list-shaped data (exactly the case here).
;; This is a real bug worth knowing about (see NOTES.md), but it's in
;; the general engine, not in the mode compiler -- fixing it is out of
;; scope for this file, which routes around it below by cross-checking
;; against a small ordinary-Prolog helper predicate (natural cons-
;; pattern head matching, no CAR/CDR-in-LISP-EVAL) instead of calling
;; the CAR/CDR-based moded predicate's own definition through (?- ...).
(callable car)
(callable cdr)
(callable cons)
(callable reverse)

(format t "~%== listsum: an INPUT list read with car/cdr (inline +/- syntax) ==~%")
;; listsum(+List, +Acc, -Sum) -- List and Acc are inputs, Sum is the
;; output. Acc is a running-total accumulator threaded through so the
;; recursive call stays the clause's LAST goal (required for the moded
;; compiler's tail-call path -- see mode-compiler.lisp's banner comment).
;; Position 1 is the literal NIL in the base case and the annotated
;; +LST in the recursive case; *det-mode-progress* merges the two across
;; clauses (see mode-compiler.lisp), so no explicit (mode ...) call is
;; needed here -- MODED-LISTSUM-3 exists by the time this file gets to
;; using it below.
(<- (listsum nil +acc -sum) (unify ?sum ?acc))
(<- (listsum +lst +acc -sum)
    (lisp-eval ?h (car ?lst))
    (lisp-eval ?t (cdr ?lst))
    (lisp-eval ?acc1 (+ ?acc ?h))
    (listsum ?t ?acc1 ?sum))

(multiple-value-bind (ok sum) (moded-listsum-3 '(1 2 3 4 5) 0)
  (format t "moded-listsum-3((1 2 3 4 5), 0) = ok=~S sum=~S (expect T 15)~%" ok sum))
(multiple-value-bind (ok sum) (moded-listsum-3 nil 0)
  (format t "moded-listsum-3(NIL, 0) = ok=~S sum=~S (expect T 0)~%" ok sum))
;; Cross-check via a plain ordinary-Prolog predicate instead of calling
;; LISTSUM itself through (?- ...) -- see the CAR/CDR/EVAL-PROLOG-FORM
;; rough edge explained in this file's banner comment. This one uses
;; native cons-pattern head matching (completely unaffected by that rough
;; edge) and only reaches LISP-EVAL for the arithmetic.
(<- (listsum-check nil ?acc ?acc))
(<- (listsum-check (?h . ?t) ?acc ?sum)
    (lisp-eval ?acc1 (+ ?acc ?h))
    (listsum-check ?t ?acc1 ?sum))
(format t "cross-check against the interpreted engine (via listsum-check): ")
(?- (listsum-check (1 2 3 4 5) 0 ?result))

(format t "~%== doubled: an OUTPUT list built with cons (explicit mode declaration) ==~%")
;; doubled3(List, Acc, Out) -- ordinary ?-syntax head, mode declared
;; explicitly afterward, on purpose: both mode-declaration front ends
;; share the same underlying compiler, so this checks that list handling
;; isn't accidentally special-cased to the inline syntax used above.
;;
;; Consing the doubled head onto Acc as we go (H2 . Acc) builds the
;; result in REVERSE order relative to List. Written this way on purpose,
;; for contrast with APPEND further down: the accumulator style here
;; keeps the recursive call as the clause's literal LAST action with
;; nothing left to do afterward, so it compiles to a real Lisp tail call
;; (see COMPILE-DET-CLAUSE's "FAST PATH") -- genuine O(1)-stack TCO, the
;; same guarantee COUNT-UP3 gets. The more natural-looking "cons the
;; current element onto whatever the recursive call returns" style
;; (which needs the recursive call's result before it can finish, so it
;; can't be a tail call) is exactly what APPEND below does instead, via
;; the new compound-output-pattern support -- DOUBLED could be rewritten
;; that way too now (it couldn't before today), but is kept as an
;; accumulator here specifically to show the TCO-preserving alternative
;; still exists and is often worth choosing when it fits the problem.
(<- (doubled3 nil ?acc ?out) (lisp-eval ?out (reverse ?acc)))
(<- (doubled3 ?lst ?acc ?out)
    (lisp-eval ?h (car ?lst))
    (lisp-eval ?t (cdr ?lst))
    (lisp-eval ?h2 (* ?h 2))
    (lisp-eval ?acc1 (cons ?h2 ?acc))
    (doubled3 ?t ?acc1 ?out))
(mode (doubled3 + + -))

;; A friendlier 2-argument entry point, tail-calling doubled3 with an
;; empty starting accumulator.
(<- (doubled ?lst ?out) (doubled3 ?lst nil ?out))
(mode (doubled + -))

(multiple-value-bind (ok out) (moded-doubled-2 '(1 2 3))
  (format t "moded-doubled-2((1 2 3)) = ok=~S out=~S (expect T (2 4 6))~%" ok out))
(multiple-value-bind (ok out) (moded-doubled-2 nil)
  (format t "moded-doubled-2(NIL) = ok=~S out=~S (expect T NIL)~%" ok out))
;; Same EVAL-PROLOG-FORM rough edge as LISTSUM above -- cross-check via
;; an ordinary-Prolog helper instead of calling DOUBLED/DOUBLED3
;; through (?- ...).
(<- (doubled-check nil nil))
(<- (doubled-check (?h . ?t) (?h2 . ?out))
    (lisp-eval ?h2 (* ?h 2))
    (doubled-check ?t ?out))
(format t "cross-check against the interpreted engine (via doubled-check): ")
(?- (doubled-check (1 2 3) ?result))

(format t "~%== append: a COMPOUND pattern nested inside a + AND a - position (Eduardo's own example) ==~%")
;; Eduardo's exact proposed head: (append (+x . +xs) +y (-x . -z)) --
;; position 1 destructures the first input list (X its head, XS its
;; tail); position 2 is the second input list, unchanged; position 3
;; constructs the output by consing X -- the SAME X as position 1, once
;; both are stripped to canonical ?-form -- onto Z, which the clause's
;; own trailing recursive call to append produces as ITS OWN third
;; output. This needed real new compiler support: until today, a
;; compound (cons) pattern in EITHER a + or a - position was a flat
;; compile-time error (see mode-tests.lisp's old "badcons" case, now
;; repurposed as a positive test) -- see mode-compiler.lisp's
;; COMPILE-DET-CLAUSE docstring for how destructuring/construction and
;; the not-quite-a-tail-call it now takes actually work.
;;
;; Position 1 and 3 are COMPOUND, so -- like a literal position -- their
;; direction can't be read off inline annotation alone (nothing about a
;; whole cons pattern says "this position is +" the way a bare +x does);
;; an explicit (mode ...) call is what actually resolves and triggers
;; compilation here, same as the parityf/ignore-secondf cases in
;; fortran-mode-tests.lisp.
(<- (append nil +y +y))
(<- (append (+x . +xs) +y (-x . -z)) (append ?xs ?y ?z))
(mode (append + + -))

(multiple-value-bind (ok out) (moded-append-3 '(1 2 3) '(4 5))
  (format t "moded-append-3((1 2 3), (4 5)) = ok=~S out=~S (expect T (1 2 3 4 5))~%" ok out))
(multiple-value-bind (ok out) (moded-append-3 nil '(4 5))
  (format t "moded-append-3(NIL, (4 5)) = ok=~S out=~S (expect T (4 5))~%" ok out))
(multiple-value-bind (ok out) (moded-append-3 '(1 2 3) nil)
  (format t "moded-append-3((1 2 3), NIL) = ok=~S out=~S (expect T (1 2 3))~%" ok out))
(format t "cross-check against the interpreted engine: ")
(?- (append (1 2 3) (4 5) ?result))

(format t "~%== append is NOT tail-call-optimized -- confirmed, and that's expected ==~%")
;; append conses X onto whatever the recursive call returns for Z, so it
;; needs that call's RESULT before it can finish building its own output
;; -- COMPILE-DET-CLAUSE falls back to MULTIPLE-VALUE-BIND instead of a
;; literal tail call, which costs one Lisp stack frame per element of
;; the first list -- same as the equivalent hand-written non-tail-
;; recursive Lisp/Prolog definition would cost. Confirm it works
;; correctly for an ordinary-sized list, and (for honest contrast with
;; count-up3/listsum's genuine O(1)-stack tail recursion) that it's not
;; immune to running out of stack on a very long one.
(dolist (n '(2000 10000 50000))
  (let ((lst (loop for i from 1 to n collect i)))
    (multiple-value-bind (ok out) (moded-append-3 lst nil)
      (format t "moded-append-3(<list of ~S>, NIL) = ok=~S, length of out=~S (expect T ~S)~%"
              n ok (and ok (length out)) n))))
;; Deliberately NOT pushed further than this in an automated test: tried
;; empirically while writing this file, a list of 100,000 blows SBCL's
;; default control stack so hard under --script that it's a genuine
;; fatal process crash (SBCL prints "Control stack exhausted" straight to
;; the terminal and exits), not a Lisp condition HANDLER-CASE can catch
;; -- 50,000 was fine, 100,000 was not, and the exact boundary is a
;; property of the OS/runtime stack size, not of this code. That's the
;; real, honest contrast with COUNT-UP3/LISTSUM above: those handle
;; 1,000,000+ deep recursion in ~10ms because SBCL turns their literal
;; tail calls into an ordinary loop, using no additional stack per
;; iteration at all; APPEND, needing the recursive call's result before
;; it can finish consing its own output, uses one real stack frame per
;; list element and WILL eventually run out, the same as the equivalent
;; hand-written non-tail-recursive Lisp or Prolog definition would.

(format t "~%all list-mode tests done~%")
(sb-ext:exit)
