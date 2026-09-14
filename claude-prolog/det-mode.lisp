;;; det-mode.lisp -- mode-declared predicates that work as ordinary Prolog
;;; queries (?-/?-all) right out of the box, with no workaround needed.
;;;
;;; This is the counterpart to 6sum.lisp's listsum/doubled, which need a
;;; separate "-check" predicate to be queried via ?- because their bodies
;;; do (lisp-eval ?h (car ?lst)) / (lisp-eval ?t (cdr ?lst)) -- and
;;; eval-prolog-form mishandles the case where the dereferenced variable
;;; turns out to be bound to an actual list, mistaking the list's own car
;;; for a function name to call (see NOTES.md, "Known rough edges").
;;;
;;; Every predicate below avoids that trap in one of two ways:
;;;   (a) its lisp-eval calls only ever touch numbers (arithmetic,
;;;       comparisons) -- never a variable that might be bound to a cons; or
;;;   (b) it destructures/constructs lists purely through cons-PATTERN
;;;       matching in the clause head (the (?x . ?xs) idiom, or the
;;;       compound +/- head-pattern support added 2026-09-14) -- again,
;;;       no lisp-eval on a list value anywhere.
;;; Either way, the general (interpreted) engine that ?- drives never goes
;;; near eval-prolog-form's bug, so these are queryable exactly like any
;;; hand-written Prolog predicate, in addition to being callable as fast
;;; direct Lisp functions once mode-compiled.
;;;
;;; This file only DEFINES the predicates (clauses + mode declarations) --
;;; it doesn't call any of them. Call them yourself after loading, three
;;; ways:
;;;   * direct compiled function:  (moded-count-up-3 0 10)
;;;       -- only the + (input) args go in, positionally; returns
;;;          (values ok output...), so use multiple-value-bind or
;;;          multiple-value-list to see anything past the first value.
;;;   * ordinary query:            (?- (count-up 0 10 ?result))
;;;   * with backtracking:         (?-all (minmax 9 3 ?lo ?hi))

(load "prolog-engine.lisp")
(load "mode-compiler.lisp")

;;; ---------------------------------------------------------------------
;;; 1. count-up: arithmetic only, no lists at all -- the simplest case
;;;    that "just works" via mode declaration AND via ?-. Its lisp-eval
;;;    calls, (>= ?n ?stop) and (+ ?n 1), only ever dereference NUMBERS --
;;;    never a variable bound to a list -- so eval-prolog-form's bug
;;;    never gets a chance to fire.
;;; ---------------------------------------------------------------------

(<- (count-up ?n ?stop ?out)
    (lisp-eval t (>= ?n ?stop))
    !
    (unify ?out ?n))
(<- (count-up ?n ?stop ?out)
    (lisp-eval ?next (+ ?n 1))
    (count-up ?next ?stop ?out))
(mode (count-up + + -))

;;; ---------------------------------------------------------------------
;;; 2. parity: a fixed/literal output, still fine via ?- (unification,
;;;    no lisp-eval on anything but a number).
;;; ---------------------------------------------------------------------

(<- (parity-rec 0 even) !)
(<- (parity-rec 1 odd) !)
(<- (parity-rec ?n ?p)
    (lisp-eval t (> ?n 1))
    (lisp-eval ?n2 (- ?n 2))
    (parity-rec ?n2 ?p))
(mode (parity-rec + -))



;;; ---------------------------------------------------------------------
;;; 3. minmax: two outputs at once, still plain arithmetic underneath.
;;; ---------------------------------------------------------------------

(<- (minmax ?a ?b ?lo ?hi)
    (lisp-eval t (<= ?a ?b)) !
    (unify ?lo ?a) (unify ?hi ?b))
(<- (minmax ?a ?b ?lo ?hi)
    (unify ?lo ?b) (unify ?hi ?a))
(mode (minmax + + - -))

;;; ---------------------------------------------------------------------
;;; 4. firstof: destructures a list, but ONLY via cons-pattern matching
;;;    in the head -- (?x . ?xs) -- never via (car ?lst) inside lisp-eval.
;;;    This is the list case that was always safe, even before the
;;;    2026-09-14 compound-pattern extension (a single-level (?x . ?xs)
;;;    pattern has always been handled fine by the engine's own unifier
;;;    for ordinary interpreted clauses).
;;; ---------------------------------------------------------------------

(<- (firstof (?x . ?xs) ?x) !)
(mode (firstof + -))

;;; ---------------------------------------------------------------------
;;; 5. append: the flagship compound-pattern example -- destructures its
;;;    first list AND builds its output list purely through cons patterns
;;;    in the clause heads, (+x . +xs) / (-x . -z). No lisp-eval anywhere
;;;    in this predicate at all, so nothing can trip the bug.
;;; ---------------------------------------------------------------------

(<- (append nil +y +y))
(<- (append (+x . +xs) +y (-x . -z)) (append ?xs ?y ?z))
(mode (append + + -))

(format t "det-mode.lisp loaded: count-up/3, parity/2, minmax/4, firstof/2, append/3 defined and mode-compiled.~%")

(<- (listsum2 nil +acc -sum) (unify ?sum ?acc))
(<- (listsum2 (+h . +t) +acc -sum)
    (lisp-eval ?acc1 (+ ?acc ?h))
    (listsum2 ?t ?acc1 ?sum))
(mode (listsum2 + + -))

(<- (doubled2 nil nil) !)
(<- (doubled2 (+h . +t) (-h2 . -t2))
    (lisp-eval ?h2 (* ?h 2))
    (doubled2 ?t ?t2))
(mode (doubled2 + -))
