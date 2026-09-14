(load "prolog-engine.lisp")
(load "mode-compiler.lisp")

(format t "~%== count-up3, moded, correctness ==~%")
(<- (count-up3 ?n ?stop ?out)
    (lisp-eval t (>= ?n ?stop))
    !
    (unify ?out ?n))
(<- (count-up3 ?n ?stop ?out)
    (lisp-eval ?next (+ ?n 0.01))
    (count-up3 ?next ?stop ?out))
(mode (count-up3 + + -))
(format t "moded-count-up3-3(0, 100) = ~S (expect T 100.00295)~%"
        (multiple-value-list (moded-count-up3-3 0 100)))
(format t "cross-check against interpreted engine: ")
(?- (count-up3 0 100 ?result))

(format t "~%== literal output pattern (base case returns a fixed literal) ==~%")
(<- (parity 0 even) !)
(<- (parity ?n odd) (lisp-eval t (= ?n 1)) !)
(mode (parity + -))
(format t "moded-parity-2(0) = ~S (expect T EVEN)~%" (multiple-value-list (moded-parity-2 0)))
(format t "moded-parity-2(1) = ~S (expect T ODD)~%" (multiple-value-list (moded-parity-2 1)))
(format t "moded-parity-2(2) = ~S (expect NIL -- no clause matches)~%" (multiple-value-list (moded-parity-2 2)))

(format t "~%== repeated input variable (equality check between two + positions) ==~%")
(<- (samev ?x ?x yes) !)
(<- (samev ?x ?y no))
(mode (samev + + -))
(format t "moded-samev-3(5,5) = ~S (expect T YES)~%" (multiple-value-list (moded-samev-3 5 5)))
(format t "moded-samev-3(5,7) = ~S (expect T NO)~%" (multiple-value-list (moded-samev-3 5 7)))

(format t "~%== underscore in an input position (wildcard, no binding) ==~%")
(<- (ignore-second ?x _ ?x) !)
(mode (ignore-second + + -))
(format t "moded-ignore-second-3(1, whatever) = ~S (expect T 1)~%"
        (multiple-value-list (moded-ignore-second-3 1 'whatever)))

(format t "~%== two arithmetic steps + multiple outputs ==~%")
(<- (minmax ?a ?b ?lo ?hi)
    (lisp-eval t (<= ?a ?b)) !
    (unify ?lo ?a) (unify ?hi ?b))
(<- (minmax ?a ?b ?lo ?hi)
    (unify ?lo ?b) (unify ?hi ?a))
(mode (minmax + + - -))
(format t "moded-minmax-4(3,9) = ~S (expect T 3 9)~%" (multiple-value-list (moded-minmax-4 3 9)))
(format t "moded-minmax-4(9,3) = ~S (expect T 3 9)~%" (multiple-value-list (moded-minmax-4 9 3)))

(format t "~%== compound pattern in a + position (car of a list) ==~%")
;; This used to be this file's "badcons" error case -- compound (cons)
;; patterns in + positions were unsupported when this test was first
;; written. That restriction was lifted 2026-09-14 (see mode-compiler.lisp's
;; banner comment and COMPILE-DET-CLAUSE's docstring, and 6sum.lisp for the
;; fuller list-processing tests, including APPEND, that motivated it) --
;; this is now a legitimate predicate, not an error case, so it's kept
;; here (renamed) as a regression check that simple car-destructuring
;; still works.
(<- (firstof (?x . ?xs) ?x) !)
(mode (firstof + -))
(format t "moded-firstof-2((a b c)) = ~S (expect T A)~%" (multiple-value-list (moded-firstof-2 '(a b c))))
(format t "moded-firstof-2(not-a-list) = ~S (expect NIL -- consp guard fails)~%" (multiple-value-list (moded-firstof-2 'not-a-list)))

(format t "~%== compile-time error: non-tail moded call (expect a clear error) ==~%")
(<- (helperA ?x ?y) (unify ?y ?x) !)
(mode (helperA + -))
(<- (badnontail ?x ?y ?z) (helperA ?x ?y) (unify ?z 1) !)
(handler-case (progn (mode (badnontail + - -)) (format t "NO ERROR RAISED -- BUG~%"))
  (error (e) (format t "correctly rejected: ~A~%" e)))

(format t "~%== compile-time error: calling an unmoded predicate (expect a clear error) ==~%")
(<- (unmoded-helper ?x ?x))
(<- (badcall ?x ?y) (unmoded-helper ?x ?y) !)
(handler-case (progn (mode (badcall + -)) (format t "NO ERROR RAISED -- BUG~%"))
  (error (e) (format t "correctly rejected: ~A~%" e)))

(format t "~%== compile-time error: output position with no producer at all (expect a clear error) ==~%")
;; ?y is never bound anywhere -- no head input establishes it, no body
;; step binds it, and there's no trailing moded call to supply it either.
(<- (badnoproducer ?x ?y) (lisp-eval t (> ?x 0)) !)
(handler-case (progn (mode (badnoproducer + -)) (format t "NO ERROR RAISED -- BUG~%"))
  (error (e) (format t "correctly rejected: ~A~%" e)))

(format t "~%== compile-time error: output has no producer even though a moded call happens (expect a clear error) ==~%")
;; badproducer2's own output Z isn't bound by anything, and helperA/2's
;; single output is named W, not Z -- the mismatch (a trailing moded call
;; whose own out-names don't cover this clause's remaining holes) must
;; still be caught, not silently miscompiled into referencing a
;; nonexistent binding.
(<- (badproducer2 ?x ?z) ! (helperA ?x ?w))
(handler-case (progn (mode (badproducer2 + -)) (format t "NO ERROR RAISED -- BUG~%"))
  (error (e) (format t "correctly rejected: ~A~%" e)))

(format t "~%all mode-compiler correctness tests done~%")
(sb-ext:exit)
